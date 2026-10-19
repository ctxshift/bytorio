package resources

import "core:mem"
import "core:math"
import "base:runtime"
import w "../resourcewire"

Kind :: enum {Empty, Texture, Sample}
Slot :: struct {
    generation: u32,
    kind: Kind,
    format, width, height, channels, rate: u32,
    data: []u8,
}
Registry :: struct {
    session, sequence: u32,
    tick: u64,
    initialized: bool,
    slots: [w.maxSlots]Slot,
    bytes: int,
    error: string,
    command: int,
}
PACKET_BYTES :: w.headerBytes+w.maxCommands*w.commandBytes+w.maxPayload
PAYLOAD_OFFSET :: w.headerBytes+w.maxCommands*w.commandBytes

u16le :: proc(b:[]u8, at:int) -> u32 {return u32(b[at])|u32(b[at+1])<<8}
u32le :: proc(b:[]u8, at:int) -> u32 {return u16le(b,at)|u16le(b,at+2)<<16}
put32 :: proc(b:[]u8, at:int, value:u32) {for i in 0..<4 {b[at+i]=u8(value>>u32(i*8))}}
within :: proc(offset,size:u32, length:int) -> bool {return u64(offset)+u64(size)<=u64(length)}
close :: proc(r:^Registry) {
    when ODIN_ARCH==.wasm32 {context.allocator=runtime.default_wasm_allocator()}
    for &slot in r.slots {delete(slot.data)};r^={}
}
reset :: proc(r:^Registry, session:u32) -> bool {
    close(r)
    if session==0 {r.error="zero resource session";return false}
    r.session=session
    for &slot in r.slots {slot.generation=1}
    return true
}
fail :: proc(r:^Registry, message:string) -> bool {r.error=message;return false}

// The caller owns a snapshot: no guest call or pointer survives into this function.
// Shadow metadata and copy-on-write bytes make validation/allocation atomic.
submit :: proc(r:^Registry, packet:[]u8, budget:=w.maxResourceBytes) -> bool {
    when ODIN_ARCH==.wasm32 {context.allocator=runtime.default_wasm_allocator()}
    r.error="";r.command=-1
    if len(packet)<w.headerBytes || len(packet)>PACKET_BYTES {return fail(r,"invalid resource packet size")}
    if u32le(packet,0)!=w.magic || u32le(packet,4)!=w.abi || u32le(packet,8)!=w.headerBytes {return fail(r,"unsupported resource packet header")}
    if r.session==0 || u32le(packet,12)!=r.session {return fail(r,"stale resource session")}
    sequence:=u32le(packet,28)
    tick:=u64(u32le(packet,16))|u64(u32le(packet,20))<<32
    phase:=u32le(packet,24)
    if r.sequence==max(u32) || sequence!=r.sequence+1 {return fail(r,"resource sequence mismatch")}
    if (!r.initialized && (phase!=0 || tick!=0)) || (r.initialized && (phase!=1 || tick!=r.tick+1)) {return fail(r,"resource tick or phase mismatch")}
    for byte in packet[52:64] {if byte!=0 {return fail(r,"nonzero resource header flags")}}
    count:=u32le(packet,32)
    payload_size:=u32le(packet,48)
    payload_offset:=u64(w.headerBytes)+u64(count)*w.commandBytes
    if count>w.maxCommands || u32le(packet,36)!=w.headerBytes || u32le(packet,40)!=count*w.commandBytes || u64(u32le(packet,44))!=payload_offset || payload_size>w.maxPayload || payload_offset+u64(payload_size)!=u64(len(packet)) {return fail(r,"invalid resource packet regions")}
    payload:=packet[int(payload_offset):]
    shadow:=r.slots
    committed:=false
    defer {
        if !committed {for slot,i in shadow {if raw_data(slot.data)!=raw_data(r.slots[i].data) {delete(slot.data)}}}
    }
    retained:=r.bytes+len(packet)
    if retained>budget {return fail(r,"resource budget exceeded by packet snapshot")}
    for index in 0..<int(count) {
        r.command=index
        cmd:=packet[w.headerBytes+index*w.commandBytes:][:w.commandBytes]
        op,id:=u16le(cmd,0),u32le(cmd,8)
        if u16le(cmd,2)!=w.commandBytes || u32le(cmd,4)!=0 || u32le(cmd,28)!=0 {return fail(r,"invalid resource command header")}
        if op<w.op_create_texture || op>w.op_destroy_sample {return fail(r,"unknown resource opcode")}
        slot_index:=id&65535
        generation:=id>>16
        if slot_index==0 || slot_index>w.maxSlots || generation==0 {return fail(r,"invalid resource handle")}
        slot:=&shadow[slot_index-1]
        if slot.generation!=generation {return fail(r,"stale resource generation")}
        args_offset,args_size:=u32le(cmd,12),u32le(cmd,16)
        data_offset,data_size:=u32le(cmd,20),u32le(cmd,24)
        destroying:=op==w.op_destroy_texture || op==w.op_destroy_sample
        expected_args:=u32(0) if destroying else u32(w.descriptorBytes)
        if args_size!=expected_args || args_offset%4!=0 || !within(args_offset,args_size,len(payload)) || !within(data_offset,data_size,len(payload)) {return fail(r,"resource argument or data range outside payload")}
        if (args_size==0 && args_offset!=0) || (data_size==0 && data_offset!=0) {return fail(r,"noncanonical empty resource range")}
        args:[8]u32
        for i in 0..<int(args_size/4) {args[i]=u32le(payload,int(args_offset)+i*4)}
        creating:=op==w.op_create_texture || op==w.op_create_sample
        kind:=Kind.Texture if op==w.op_create_texture || op==w.op_write_texture || op==w.op_destroy_texture else Kind.Sample
        if creating {
            if slot.kind!=.Empty || data_size!=0 {return fail(r,"resource slot already live or unexpected creation data")}
            size:u64
            if kind==.Texture {
                if (args[0]!=w.format_index8 && args[0]!=w.format_rgba8) || args[1]==0 || args[1]>w.maxImageAxis || args[2]==0 || args[2]>w.maxImageAxis {return fail(r,"invalid texture descriptor")}
                for value in args[3:] {if value!=0 {return fail(r,"nonzero texture descriptor padding")}}
                size=u64(args[1])*u64(args[2])*(4 if args[0]==w.format_rgba8 else 1)
            } else {
                if args[0]!=w.format_f32 || args[1]==0 || (args[2]!=1 && args[2]!=2) || args[3]<8000 || args[3]>96000 {return fail(r,"invalid sample descriptor")}
                for value in args[4:] {if value!=0 {return fail(r,"nonzero sample descriptor padding")}}
                size=u64(args[1])*u64(args[2])*4
            }
            if size>u64(budget) || u64(retained)+size>u64(budget) {return fail(r,"resource allocation exceeds budget")}
            pointer,err:=mem.alloc(int(size),1)
            if err!=nil {return fail(r,"resource allocation failed")}
            data:=(cast([^]u8)pointer)[:int(size)]
            mem.zero(raw_data(data),len(data))
            slot^=Slot{generation=generation,kind=kind,format=args[0],width=args[1],height=args[2] if kind==.Texture else 0,channels=args[2] if kind==.Sample else 0,rate=args[3],data=data}
            retained+=len(data)
        } else {
            if slot.kind!=kind {return fail(r,"wrong resource type or destroyed handle")}
            original:=&r.slots[slot_index-1]
            owned:=raw_data(slot.data)!=raw_data(original.data)
            if destroying {
                if data_size!=0 {return fail(r,"unexpected destroy data")}
                if owned {retained-=len(slot.data);delete(slot.data)}
                // Generation 65536 retires this slot for the session.
                slot^=Slot{generation=generation+1}
                continue
            }
            src:=payload[int(data_offset):][:int(data_size)]
            if kind==.Texture {
                x,y,width,height,offset,stride:=args[0],args[1],args[2],args[3],args[4],args[5]
                bpp:=u64(4) if slot.format==w.format_rgba8 else u64(1)
                if width==0 || height==0 || u64(x)+u64(width)>u64(slot.width) || u64(y)+u64(height)>u64(slot.height) || u64(stride)<u64(width)*bpp || u64(offset)+u64(height-1)*u64(stride)+u64(width)*bpp>u64(len(src)) || args[6]!=0 || args[7]!=0 {return fail(r,"invalid texture upload bounds or stride")}
                if slot.format==w.format_rgba8 {
                    for row in 0..<int(height) {for col in 0..<int(width) {
                        p:=int(offset)+row*int(stride)+col*4
                        if src[p]>src[p+3] || src[p+1]>src[p+3] || src[p+2]>src[p+3] {return fail(r,"RGBA upload must be premultiplied")}
                    }}
                }
            } else {
                if args[1]==0 || u64(args[0])+u64(args[1])>u64(slot.width) || u64(data_size)!=u64(args[1])*u64(slot.channels)*4 {return fail(r,"invalid PCM frame range")}
                for value in args[2:] {if value!=0 {return fail(r,"nonzero PCM descriptor padding")}}
                for at:=0;at<len(src);at+=4 {
                    value:=transmute(f32)u32le(src,at)
                    if math.is_nan(value) || math.is_inf(value) {return fail(r,"nonfinite PCM sample")}
                }
            }
            if !owned {
                if retained+len(slot.data)>budget {return fail(r,"resource snapshot exceeds budget")}
                pointer,err:=mem.alloc(len(slot.data),1)
                if err!=nil {return fail(r,"resource snapshot allocation failed")}
                data:=(cast([^]u8)pointer)[:len(slot.data)]
                copy(data,slot.data);slot.data=data;retained+=len(data)
            }
            if kind==.Texture {
                bpp:=4 if slot.format==w.format_rgba8 else 1
                for row in 0..<int(args[3]) {
                    dst:=(int(args[1])+row)*int(slot.width)*bpp+int(args[0])*bpp
                    src_at:=int(args[4])+row*int(args[5])
                    copy(slot.data[dst:][:int(args[2])*bpp],src[src_at:][:int(args[2])*bpp])
                }
            } else {copy(slot.data[int(args[0]*slot.channels*4):],src)}
        }
    }
    r.bytes=0
    for slot,i in shadow {
        if raw_data(slot.data)!=raw_data(r.slots[i].data) {delete(r.slots[i].data)}
        r.bytes+=len(slot.data)
    }
    r.slots=shadow;r.sequence=sequence;r.tick=tick;r.initialized=true;r.command=-1
    committed=true
    return true
}

hash :: proc(r:^Registry) -> u32 {
    result:=u32(2166136261)
    for slot,i in r.slots {
        if slot.kind==.Empty {continue}
        values:=[7]u32{u32(i+1)|slot.generation<<16,u32(slot.kind),slot.format,slot.width,slot.height,slot.channels,slot.rate}
        for value in values {for shift in 0..<4 {result=(result~u32(u8(value>>u32(shift*8))))*16777619}}
        for value in slot.data {result=(result~u32(value))*16777619}
    }
    return result
}

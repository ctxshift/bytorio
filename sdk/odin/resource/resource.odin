package resource

import w "../../../runtime/odin/resourcewire"
import r "../../../runtime/odin/resources"
VERSION :: w.version

Handle :: struct {session,id:u32}
Local_Slot :: struct {generation,kind,format,channels:u32}
packet:[r.PACKET_BYTES]u8
slots:[w.maxSlots]Local_Slot
session,sequence,count,payload_size:u32
tick:u64
phase:u32
active,sealed:bool
error:string
fail :: proc(message:string) {if error=="" {error=message}}
configure :: proc(value:u32) -> bool {
    if value==0 || active || sealed {return false}
    session=value;sequence=0;error="";count=0;payload_size=0
    slots={};for &slot in slots {slot.generation=1}
    return true
}
begin :: proc(value:u64) {
    if sealed {fail("resource packet was not acknowledged");return}
    count=0;payload_size=0;tick=value;phase=0 if value==0 else 1;active=true
}
end :: proc() {active=false}
valid :: proc(ok:bool,message:string) -> bool {
    if error!="" {return false}
    if !ok {fail(message);return false}
    return true
}
ready :: proc() -> bool {return valid(session!=0 && active && !sealed,"resource operations require a configured init/update callback")}
reserve :: proc(kind:u32,format:u32,channels:u32=0) -> Handle {
    if !ready() {return {}}
    for &slot,i in slots {if slot.kind==0 && slot.generation<=65535 {slot.kind=kind;slot.format=format;slot.channels=channels;return {session,u32(i+1)|slot.generation<<16}}}
    fail("resource slot capacity exceeded");return {}
}
check :: proc(handle:Handle,kind:u32) -> bool {
    if !ready() || !valid(handle.session==session,"stale resource session") {return false}
    index:=handle.id&65535
    if !valid(index>0 && index<=w.maxSlots,"invalid resource slot") {return false}
    slot:=slots[index-1]
    return valid(slot.kind==kind && slot.generation==handle.id>>16,"wrong resource kind or stale generation")
}
emit :: proc(op:u32,handle:Handle,args:[]u32=nil,data:[]u8=nil) {
    if !ready() {return}
    needed:=(payload_size+3)&~u32(3)
    if !valid(count<w.maxCommands && u64(needed)+u64(len(args)*4)+u64(len(data))<=w.maxPayload,"resource staging capacity exceeded") {return}
    args_at:=needed;data_at:=args_at+u32(len(args)*4)
    for value,i in args {r.put32(packet[:],r.PAYLOAD_OFFSET+int(args_at)+i*4,value)}
    if len(data)>0 {copy(packet[r.PAYLOAD_OFFSET+int(data_at):][:len(data)],data)}
    at:=w.headerBytes+int(count)*w.commandBytes
    for &byte in packet[at:][:w.commandBytes] {byte=0}
    packet[at]=u8(op);packet[at+2]=w.commandBytes
    r.put32(packet[:],at+8,handle.id)
    r.put32(packet[:],at+12,args_at if len(args)>0 else 0);r.put32(packet[:],at+16,u32(len(args)*4))
    r.put32(packet[:],at+20,data_at if len(data)>0 else 0);r.put32(packet[:],at+24,u32(len(data)))
    count+=1;payload_size=data_at+u32(len(data))
}
destroy :: proc(handle:Handle,kind:u32) {
    if !check(handle,kind) {return}
    emit(w.op_destroy_texture if kind==1 else w.op_destroy_sample,handle)
    slot:=&slots[(handle.id&65535)-1];slot.kind=0;slot.generation+=1
}
commit :: proc() -> u32 {
    if session==0 {return 0}
    if error!="" || active || sealed || sequence==max(u32) {fail("cannot seal resource packet");return 0}
    sequence+=1
    for &byte in packet[:w.headerBytes] {byte=0}
    payload_offset:=u32(w.headerBytes)+count*w.commandBytes
    copy(packet[int(payload_offset):][:int(payload_size)],packet[r.PAYLOAD_OFFSET:][:int(payload_size)])
    fields:=[13]u32{w.magic,w.abi,w.headerBytes,session,u32(tick),u32(tick>>32),phase,sequence,count,w.headerBytes,count*w.commandBytes,payload_offset,payload_size}
    for field,i in fields {r.put32(packet[:],i*4,field)}
    sealed=true
    return u32(uintptr(&packet))
}
ack :: proc(value:u32) -> bool {
    if !sealed || value!=sequence {fail("resource acknowledgement mismatch");return false}
    sealed=false;return true
}
packet_size :: proc "contextless" () -> u32 {return w.headerBytes+count*w.commandBytes+payload_size}

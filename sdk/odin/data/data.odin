package data

import w "../../../runtime/odin/resourcewire"
import "base:runtime"
import transport "../resource"
Pixel_Format :: enum u32 {Index8=w.format_index8,RGBA8=w.format_rgba8}
Pixel_Buffer :: struct {format:Pixel_Format,width,height:int,bytes:[]u8,allocator:runtime.Allocator}
PCM_Buffer :: struct {frames,channels:int,samples:[]f32,allocator:runtime.Allocator}
pixels :: proc(format:Pixel_Format,width,height:int) -> Pixel_Buffer {
    when ODIN_ARCH==.wasm32 {if context.allocator.procedure==runtime.nil_allocator_proc {context.allocator=runtime.default_wasm_allocator()}}
    if !transport.valid((format==.Index8 || format==.RGBA8) && width>=1 && width<=w.maxImageAxis && height>=1 && height<=w.maxImageAxis,"invalid pixel buffer descriptor") {return {}}
    bytes,err:=make([]u8,width*height*(4 if format==.RGBA8 else 1))
    if err!=nil {transport.fail("pixel buffer allocation failed");return {}}
    return {format,width,height,bytes,context.allocator}
}
pcm :: proc(frames,channels:int) -> PCM_Buffer {
    when ODIN_ARCH==.wasm32 {if context.allocator.procedure==runtime.nil_allocator_proc {context.allocator=runtime.default_wasm_allocator()}}
    if !transport.valid(frames>=1 && frames<=w.maxPayload/4 && (channels==1 || channels==2) && u64(frames)*u64(channels)*4<=w.maxPayload,"invalid PCM buffer descriptor") {return {}}
    samples,err:=make([]f32,frames*channels)
    if err!=nil {transport.fail("PCM buffer allocation failed");return {}}
    return {frames,channels,samples,context.allocator}
}
free_pixels :: proc(buffer:^Pixel_Buffer) {if len(buffer.bytes)>0 {delete(buffer.bytes,buffer.allocator)};buffer^={}}
free_pcm :: proc(buffer:^PCM_Buffer) {if len(buffer.samples)>0 {delete(buffer.samples,buffer.allocator)};buffer^={}}

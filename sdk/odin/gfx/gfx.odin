package gfx

import data "../data"
import t "../resource"
import w "../../../runtime/odin/resourcewire"
Texture :: distinct t.Handle
Texture_Desc :: struct {format:data.Pixel_Format,width,height:u32}
Rect :: struct {x,y,width,height:u32}
Upload :: struct {offset_bytes,stride_bytes:u32}
texture :: proc(desc:Texture_Desc) -> Texture {
    if !t.valid((desc.format==.Index8 || desc.format==.RGBA8) && desc.width>0 && desc.width<=w.maxImageAxis && desc.height>0 && desc.height<=w.maxImageAxis,"invalid texture descriptor") {return {}}
    handle:=t.reserve(1,u32(desc.format))
    args:=[8]u32{u32(desc.format),desc.width,desc.height,0,0,0,0,0}
    t.emit(w.op_create_texture,handle,args[:])
    return Texture(handle)
}
upload :: proc(target:Texture,rect:Rect,pixels:data.Pixel_Buffer,opts:=Upload{}) {
    handle:=t.Handle(target)
    if !t.check(handle,1) {return}
    if !t.valid(u32(pixels.format)==t.slots[(handle.id&65535)-1].format && pixels.width>0 && pixels.height>0 && len(pixels.bytes)>0,"texture and pixel buffer formats differ or buffer is empty") {return}
    stride:=opts.stride_bytes
    if stride==0 {stride=u32(pixels.width)*(4 if pixels.format==.RGBA8 else 1)}
    args:=[8]u32{rect.x,rect.y,rect.width,rect.height,opts.offset_bytes,stride,0,0}
    t.emit(w.op_write_texture,handle,args[:],pixels.bytes)
}
destroy :: proc(target:Texture) {t.destroy(t.Handle(target),1)}

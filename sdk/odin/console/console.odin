package console

import "base:runtime"
import abi "../../../runtime/odin/abi"
import g "../../../runtime/odin/graphics"

VERSION :: "0.1.0"
VERSION_WORD :: u32(256)
DT :: 1.0/60.0
Button :: enum u32 {Left=1,Right=2,Up=4,Down=8,Action=16}
Display :: enum u32 {High=abi.DISPLAY_HIGH,Low=abi.DISPLAY_LOW}
Callbacks :: struct {init: proc(), update: proc(dt:f64), draw: proc()}
Config :: struct {graphics: []u8, display: Display}

callbacks: Callbacks
graphics: []u8
frame: abi.Frame
held, down, up, clock, random_state: u32
pointer_active: bool
pointer_x,pointer_y: f64
diagnostic: [1024]u8
diagnostic_size: u32

fail :: proc(message:string) {
    if diagnostic_size != 0 {return}
    diagnostic_size=u32(min(len(message),len(diagnostic)))
    for i in 0..<int(diagnostic_size) {diagnostic[i]=message[i]}
}
valid :: proc(ok:bool,message:string) -> bool {
    if diagnostic_size != 0 {return false}
    if !ok {fail(message);return false}
    return true
}
coordinates :: proc(x,y:int) -> bool {return valid(x>=-4096 && x<=4096 && y>=-4096 && y<=4096,"coordinates outside supported range")}

// Called by the generated entry point. Game authors provide ordinary callbacks.
start :: proc(hooks:Callbacks,config:Config) {
    callbacks,graphics=hooks,config.graphics
    diagnostic_size=0
    held,down,up,clock=0,0,0,0
    pointer_active=false;pointer_x,pointer_y=0,0
    random_state=1
    frame={version=abi.VERSION,clear=0xff322015,sprite_x=-4096,sprite_y=-4096}
    g.begin()
    mode:=abi.DISPLAY_HIGH if u32(config.display)==0 else u32(config.display)
    if !valid(g.set_display(mode),"unsupported display mode") {return}
    if !valid(len(graphics)>0 && len(graphics)<=abi.MAX_GRAPHICS_BYTES,"invalid graphics packet length") {return}
    if !valid(hooks.init!=nil && hooks.update!=nil && hooks.draw!=nil,"missing game callback") {return}
    callbacks.init()
}
display :: proc(mode:Display) {
    if diagnostic_size==0 && !g.set_display(u32(mode)) {fail("unsupported display mode")}
}
size :: proc() -> (int,int) {return int(g.display_mode>>16),int(g.display_mode&65535)}
rgb :: proc(r,g,b:int) -> u32 {
    if !valid(r>=0&&r<=255&&g>=0&&g<=255&&b>=0&&b<=255,"color channel outside supported range") {return 0xff000000}
    return 0xff000000|u32(b)<<16|u32(g)<<8|u32(r)
}
clear :: proc(color:u32) {if valid(color>>24==255,"colors must be opaque") {frame.clear=color}}
rect :: proc(x,y,w,h:int,color:u32) {
    if coordinates(x,y) && valid(color>>24==255,"colors must be opaque") && valid(w>=0&&w<=4096&&h>=0&&h<=4096,"rectangle dimensions outside supported range") {g.rect(x,y,w,h,color)}
}
sprite :: proc(id,x,y:int,scale:=1) {
    if coordinates(x,y) && valid(id>=0&&id<256&&scale>=1&&scale<=8,"invalid sprite ID or scale") {g.sprite(id,x,y,scale)}
}
sprite_size :: proc(id,x,y,w,h:int) {
    if coordinates(x,y) && valid(id>=0&&id<256&&w>=1&&w<=128&&h>=1&&h<=128,"invalid sprite ID or size") {g.sprite_size(id,x,y,w,h)}
}
text :: proc(value:string,x,y:int,color:u32) {
    if !coordinates(x,y) || !valid(color>>24==255,"colors must be opaque") || !valid(len(value)<=1024,"text command exceeds 1024 bytes") {return}
    for char in value {if !valid(char>=0&&char<128,"text must be ASCII") {return}}
    g.text(value,x,y,color)
}
buttons :: proc() -> u32 {return held}
button :: proc(key:Button) -> bool {return held&u32(key)!=0}
pressed :: proc(key:Button) -> bool {return down&u32(key)!=0}
released :: proc(key:Button) -> bool {return up&u32(key)!=0}
pointer :: proc() -> (bool,f64,f64) {return pointer_active,pointer_x,pointer_y}
ticks :: proc() -> u32 {return clock}
sound :: proc() {if diagnostic_size==0 {frame.sounds+=1}}
seed :: proc(value:u32) {random_state=0x6d2b79f5 if value==0 else value}
random_u32 :: proc() -> u32 {
    random_state~=random_state<<13
    random_state~=random_state>>17
    random_state~=random_state<<5
    return random_state
}
debug_position :: proc(x,y:f64) {
    if valid(x>=-4096&&x<=4096&&y>=-4096&&y<=4096,"invalid development position") {frame.x,frame.y=x,y}
}

@(export) game_abi :: proc "c" () -> u32 {return abi.VERSION}
@(export) game_sdk_version :: proc "c" () -> u32 {return VERSION_WORD}
@(export) game_frame_size :: proc "c" () -> u32 {return abi.FRAME_BYTES}
@(export) game_display_mode :: proc "c" () -> u32 {return g.display_mode}
@(export) game_update :: proc "c" (mask,active:u32,x,y:f64) {
    context=runtime.default_context()
    if diagnostic_size!=0 {return}
    next:=mask&31
    down,up=next&~held,held&~next
    held=next
    width,height:=size()
    pointer_active=active!=0&&x>=0&&x<f64(width)&&y>=0&&y<f64(height)
    pointer_x,pointer_y=0,0
    if pointer_active {pointer_x,pointer_y=x,y}
    clock+=1
    callbacks.update(DT)
    frame.ticks=clock
}
@(export) game_draw :: proc "c" () -> u32 {
    context=runtime.default_context()
    g.begin()
    if diagnostic_size==0 {callbacks.draw()}
    if g.overflow {fail("graphics batch capacity exceeded")}
    return u32(uintptr(&frame))
}
@(export) game_commands :: proc "c" () -> u32 {return u32(uintptr(&g.commands))}
@(export) game_command_count :: proc "c" () -> u32 {return g.count}
@(export) game_command_stride :: proc "c" () -> u32 {return 32}
@(export) game_text :: proc "c" () -> u32 {return u32(uintptr(&g.text_bytes))}
@(export) game_text_size :: proc "c" () -> u32 {return g.text_count}
@(export) game_assets :: proc "c" () -> u32 {return u32(uintptr(raw_data(graphics)))}
@(export) game_assets_size :: proc "c" () -> u32 {return u32(len(graphics))}
@(export) game_error :: proc "c" () -> u32 {return u32(uintptr(&diagnostic))}
@(export) game_error_length :: proc "c" () -> u32 {return diagnostic_size}

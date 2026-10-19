package main
import "base:runtime"
import abi "../../../runtime/odin/abi"
frame: abi.Frame
invalid :: #config(DISPLAY_INVALID, false)
@(export) game_abi :: proc "c" () -> u32 {return abi.VERSION}
@(export) game_frame_size :: proc "c" () -> u32 {return abi.FRAME_BYTES}
@(export) game_init :: proc "c" () {frame = {version=abi.VERSION,clear=0xff603020,sprite_x=630,sprite_y=350}}
@(export) game_update :: proc "c" (buttons,pointer:u32,x,y:f64) {frame.ticks+=1}
@(export) game_draw :: proc "c" () -> u32 {return u32(uintptr(&frame))}
@(export) game_display_mode :: proc "c" () -> u32 {
    if invalid {return 384<<16|216}
    return abi.DISPLAY_LOW if frame.ticks >= 30 && frame.ticks < 90 else abi.DISPLAY_HIGH
}

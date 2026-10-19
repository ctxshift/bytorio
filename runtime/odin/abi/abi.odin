package abi

VERSION :: u32(1)
WIDTH :: 640
HEIGHT :: 360
// Optional game_display_mode export: high 16 bits width, low 16 bits height.
DISPLAY_HIGH :: u32(640 << 16 | 360)
DISPLAY_LOW :: u32(320 << 16 | 180)
valid_display :: proc(mode: u32) -> bool {

    return mode == DISPLAY_HIGH || mode == DISPLAY_LOW
}
FRAME_BYTES :: 40
MAX_GAME_BYTES :: 1024 * 1024
MAX_MEMORY_BYTES :: 8 * 1024 * 1024
MAX_COMMANDS :: 16384
Command :: struct {
    x, y, w, h: i32,
    color:      u32,
}
#assert(size_of(Command) == 20)
Draw_Command :: struct {
    kind:                  u32,
    x, y, w, h:            i32,
    color, offset, length: u32,
}
#assert(size_of(Draw_Command) == 32)
MAX_TEXT_BYTES :: 16384
MAX_GRAPHICS_BYTES :: 16 + 64 + 256 * 256 + 128 * 7

// Fixed-width, little-endian wire record. It contains no pointers or Odin context.
Frame :: struct {
    version:            u32,
    clear:              u32,
    sprite_x, sprite_y: i32,
    ticks, sounds:      u32,
    x, y:               f64,
}
#assert(size_of(Frame) == FRAME_BYTES)
#assert(offset_of(Frame, x) == 24)

Input :: struct {
    buttons: u32,
    pointer: bool,
    x, y:    f64,
}

smoke_input :: proc(tick: u32) -> Input {
    result: Input
    if tick < 60 {

        result.buttons = 2
    }
    if tick == 60 {

        result.buttons = 16
    }
    return result
}

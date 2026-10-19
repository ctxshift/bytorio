package abi

VERSION :: u32(1)
WIDTH :: 640
HEIGHT :: 360
// Optional game_display_mode export: high 16 bits width, low 16 bits height.
DISPLAY_DIMENSION_BITS :: 16
DISPLAY_DIMENSION_MASK :: (1 << DISPLAY_DIMENSION_BITS) - 1
DISPLAY_HIGH :: u32(640 << DISPLAY_DIMENSION_BITS | 360)
DISPLAY_LOW :: u32(320 << DISPLAY_DIMENSION_BITS | 180)
valid_display :: proc(mode: u32) -> bool {

    return mode == DISPLAY_HIGH || mode == DISPLAY_LOW
}
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

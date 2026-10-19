package abi

VERSION :: u32(1)
WIDTH :: 384
HEIGHT :: 216
FRAME_BYTES :: 40
MAX_GAME_BYTES :: 1024 * 1024
MAX_MEMORY_BYTES :: 8 * 1024 * 1024
MAX_COMMANDS :: 16384
Command :: struct { x, y, w, h: i32, color: u32 }
#assert(size_of(Command) == 20)

// Fixed-width, little-endian wire record. It contains no pointers or Odin context.
Frame :: struct {
    version: u32,
    clear: u32,
    sprite_x, sprite_y: i32,
    ticks, sounds: u32,
    x, y: f64,
}
#assert(size_of(Frame) == FRAME_BYTES)
#assert(offset_of(Frame, x) == 24)

Input :: struct {
    buttons: u32,
    pointer: bool,
    x, y: f64,
}

smoke_input :: proc(tick: u32) -> Input {
    result: Input
    if tick < 60 { result.buttons = 2 }
    if tick == 60 { result.buttons = 16 }
    return result
}

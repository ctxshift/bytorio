package abi

import "core:math"
import "core:strconv"
import "core:strings"

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

// Legacy decimal masks remain valid. Version 2 adds left-held and logical coordinates.
parse_input :: proc(token: string) -> (Input, bool) {
    result: Input
    fields := strings.split(token, ":")
    defer delete(fields)
    if len(fields) == 1 {
        mask, ok := strconv.parse_u64(token)
        if !ok || mask > INPUT_BUTTON_MASK { return {}, false }
        result.buttons = u32(mask)
        return result, true
    }
    if len(fields) != 5 || fields[0] != "v2" { return {}, false }
    mask, mask_ok := strconv.parse_u64(fields[1])
    active, active_ok := strconv.parse_u64(fields[2])
    x, x_ok := strconv.parse_f64(fields[3])
    y, y_ok := strconv.parse_f64(fields[4])
    if !mask_ok ||
       mask > INPUT_BUTTON_MASK ||
       !active_ok ||
       active > 1 ||
       !x_ok ||
       !y_ok ||
       math.is_nan(x) ||
       math.is_inf(x) ||
       math.is_nan(y) ||
       math.is_inf(y) {
        return {}, false
    }
    result = Input {
        buttons = u32(mask),
        pointer = active != 0,
        x       = x,
        y       = y,
    }
    return result, true
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

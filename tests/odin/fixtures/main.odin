package main

import abi "../../../runtime/odin/abi"
FAULT :: #config(TEST_FAULT, 0)
frame: abi.Frame

@(export) game_abi :: proc "c" () -> u32 {
    when FAULT == 2 { return 99 } else { return 1 }
}
@(export) game_frame_size :: proc "c" () -> u32 { return 40 }
@(export) game_init :: proc "c" () {
    frame.version = 1
    when FAULT == 1 { for { frame.ticks += 1 } }
    when FAULT == 5 {
        values: [4]u32
        frame.sounds = values[frame.version + 4]
    }
}
@(export) game_update :: proc "c" (_buttons, _pointer: u32, _px, _py: f64) { frame.ticks += 1 }
@(export) game_draw :: proc "c" () -> u32 {
    when FAULT == 3 { return 0x7ffffff0 }
    when FAULT == 4 { frame.sprite_x = 1000000 }
    return u32(uintptr(&frame))
}

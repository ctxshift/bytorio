package main

import abi "../../../runtime/odin/abi"
FAULT :: #config(TEST_FAULT, 0)
frame: abi.Frame
command: abi.Command

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
when FAULT >= 6 {
    @(export) game_commands :: proc "c" () -> u32 {
        when FAULT == 7 { return 0x7ffffff0 }
        when FAULT == 8 { command.w = 5000 }
        return u32(uintptr(&command))
    }
    @(export) game_command_count :: proc "c" () -> u32 {
        when FAULT == 6 { return abi.MAX_COMMANDS+1 }
        return 1
    }
}

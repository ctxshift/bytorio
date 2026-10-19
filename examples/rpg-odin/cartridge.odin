package main

import "base:runtime"
import abi "../../runtime/odin/abi"
import g "../../runtime/odin/graphics"
import "assets"

// Player ABI glue is separate from the gameplay module.
frame: abi.Frame
@(export) game_abi :: proc "c" () -> u32 { return abi.VERSION }
@(export) game_frame_size :: proc "c" () -> u32 { return abi.FRAME_BYTES }
@(export) game_init :: proc "c" () { context = runtime.default_context(); init() }
@(export) game_update :: proc "c" (buttons, _pointer: u32, _x, _y: f64) {
    context = runtime.default_context()
    update(buttons)
}
@(export) game_draw :: proc "c" () -> u32 {
    context = runtime.default_context()
    g.begin()
    draw()
    frame = abi.Frame{version=abi.VERSION, clear=0xff322015, sprite_x=-4096, sprite_y=-4096,
        ticks=s.ticks, sounds=s.sounds, x=f64(s.x), y=f64(s.y)}
    return u32(uintptr(&frame))
}
@(export) game_commands :: proc "c" () -> u32 { return u32(uintptr(&g.commands)) }
@(export) game_command_count :: proc "c" () -> u32 { return 0xffffffff if g.overflow else g.count }
@(export) game_command_stride :: proc "c" () -> u32 { return 32 }
@(export) game_text :: proc "c" () -> u32 { return u32(uintptr(&g.text_bytes)) }
@(export) game_text_size :: proc "c" () -> u32 { return g.text_count }
@(export) game_assets :: proc "c" () -> u32 { return u32(uintptr(&assets.raster)) }
@(export) game_assets_size :: proc "c" () -> u32 { return u32(size_of(assets.raster)) }

// Optional cartridge diagnostics for the development replay tool.
inspection: [10]i32
@(export) game_inspect :: proc "c" () -> u32 {
    flags := i32(s.quest) | i32(s.herb)<<1 | i32(s.won)<<2 | i32(s.complete)<<3 | i32(s.defeated)<<4
    inspection = {i32(s.x),i32(s.y),i32(s.hp),i32(s.potions),i32(s.enemy),i32(s.choice),i32(s.mode),flags,i32(s.steps),i32(s.ticks)}
    return u32(uintptr(&inspection))
}

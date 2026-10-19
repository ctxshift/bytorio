package main

import "core:math"
import "base:runtime"
import abi "../../runtime/odin/abi"

State :: struct {
    x, y, elapsed: f64,
    ticks, sounds: u32,
    previous_action: bool,
}
state: State
frame: abi.Frame

@(export) game_abi :: proc "c" () -> u32 { return abi.VERSION }
@(export) game_frame_size :: proc "c" () -> u32 { return abi.FRAME_BYTES }

@(export)
game_init :: proc "c" () {
    state = State{x = 184, y = 100, sounds = 1}
}

@(export)
game_update :: proc "c" (buttons, pressed: u32, px, py: f64) {
    dt :: 1.0 / 60.0
    state.elapsed += dt
    speed := 100 * dt
    if buttons & 1 != 0 { state.x -= speed }
    if buttons & 2 != 0 { state.x += speed }
    if buttons & 4 != 0 { state.y -= speed }
    if buttons & 8 != 0 { state.y += speed }
    if pressed != 0 { state.x, state.y = px - 8, py - 8 }
    state.x = clamp(state.x, 0, 368)
    state.y = clamp(state.y, 0, 200)
    action := buttons & 16 != 0 || pressed != 0
    if action && !state.previous_action { state.sounds += 1 }
    state.previous_action = action
    state.ticks += 1
}

@(export)
game_draw :: proc "c" () -> u32 {
    context = runtime.default_context()
    frame = abi.Frame{
        version = abi.VERSION, clear = 0xff281814,
        sprite_x = i32(state.x), sprite_y = i32(state.y + math.sin(state.elapsed * 3) * 2),
        ticks = state.ticks, sounds = state.sounds, x = state.x, y = state.y,
    }
    return u32(uintptr(&frame))
}

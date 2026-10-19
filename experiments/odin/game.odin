package main

// Compiler/ABI probe only. This is not connected to the console player.
State :: struct {
    x, y: f64,
    ticks, sounds: u32,
    previous_action: bool,
}

state: State

@(export)
game_init :: proc "c" () {
    state = State{x = 184, y = 100, sounds = 1}
}

@(export)
game_update :: proc "c" (dt: f64, buttons: u32) {
    speed := 100 * dt
    if buttons & 1 != 0 { state.x -= speed }
    if buttons & 2 != 0 { state.x += speed }
    if buttons & 4 != 0 { state.y -= speed }
    if buttons & 8 != 0 { state.y += speed }
    state.x = clamp(state.x, 0, 368)
    state.y = clamp(state.y, 0, 200)
    action := buttons & 16 != 0
    if action && !state.previous_action { state.sounds += 1 }
    state.previous_action = action
    state.ticks += 1
}

@(export)
game_x :: proc "c" () -> f64 { return state.x }

@(export)
game_y :: proc "c" () -> f64 { return state.y }

@(export)
game_ticks :: proc "c" () -> u32 { return state.ticks }

@(export)
game_sounds :: proc "c" () -> u32 { return state.sounds }

@(export)
probe_bounds :: proc "c" (index: i32) -> i32 {
    values := [4]i32{11, 22, 33, 44}
    return values[index]
}

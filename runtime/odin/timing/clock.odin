package timing

import "core:math"

SIMULATION_HZ :: 60
MAX_CATCH_UP_STEPS :: 5
MAX_RENDER_FPS :: 240
NATIVE_FRAME_RATE :: 0
UNCAPPED_FRAME_RATE :: -1
DEADLINE_EPSILON :: 1e-9

Clock :: struct {
    elapsed, accumulator, next_draw: f64,
}

advance :: proc(clock: ^Clock, delta: f64) {
    bounded := clamp(delta, 0, 0.1)
    clock.elapsed += bounded
    clock.accumulator = min(clock.accumulator + bounded, f64(MAX_CATCH_UP_STEPS) / SIMULATION_HZ)
}

take :: proc(clock: ^Clock, fps: int) -> (steps: int, render: bool) {
    steps = min(
        int(math.floor((clock.accumulator + DEADLINE_EPSILON) * SIMULATION_HZ)),
        MAX_CATCH_UP_STEPS,
    )
    clock.accumulator = max(0, clock.accumulator - f64(steps) / SIMULATION_HZ)
    render = fps <= 0 || clock.elapsed + DEADLINE_EPSILON >= clock.next_draw
    if render && fps > 0 {
        clock.next_draw =
            (math.floor((clock.elapsed + DEADLINE_EPSILON) * f64(fps)) + 1) / f64(fps)
    }
    return
}

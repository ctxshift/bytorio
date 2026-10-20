package timing_test

import timing "../../runtime/odin/timing"
import "core:testing"

@(test)
independent_rates :: proc(t: ^testing.T) {
    rates := [6]int{30, 60, 120, 144, timing.NATIVE_FRAME_RATE, timing.UNCAPPED_FRAME_RATE}
    for fps in rates {
        clock: timing.Clock
        ticks, draws: int
        // Exactly one second on a synthetic 720 Hz display. Include t=0,
        // exclude t=1 so the expected draw count does not include an endpoint.
        for frame in 0 ..< 720 {
            if frame > 0 { timing.advance(&clock, 1.0 / 720) }
            steps, render := timing.take(&clock, fps)
            ticks += steps
            if render { draws += 1 }
        }
        timing.advance(&clock, 1.0 / 720)
        steps, _ := timing.take(&clock, fps)
        ticks += steps
        testing.expect_value(t, ticks, timing.SIMULATION_HZ)
        expected := fps if fps > 0 else 720
        testing.expect_value(t, draws, expected)
    }
}

@(test)
bounded_catch_up :: proc(t: ^testing.T) {
    clock: timing.Clock
    timing.advance(&clock, 10)
    steps, render := timing.take(&clock, 30)
    testing.expect_value(t, steps, timing.MAX_CATCH_UP_STEPS)
    testing.expect(t, render)
    next_steps, next_render := timing.take(&clock, 30)
    testing.expect_value(t, next_steps, 0)
    testing.expect(t, !next_render)
}

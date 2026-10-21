package main

import "base:runtime"
import "core:math"

// Optional development state, outside the cartridge ABI.
inspection: [27]i32
@(export)
game_inspect :: proc "c" () -> u32 {
    context = runtime.default_context()
    position, _ := sample(s.distance, s.lateral)
    inspection = {
        i32(s.tick),
        i32(s.elapsed),
        i32(s.distance),
        i32(s.lateral),
        i32(s.heading),
        i32(s.speed),
        i32(s.drift),
        i32(s.charge),
        i32(s.boost),
        i32(s.hits),
        i32(s.offroad),
        i32(s.boosts),
        i32(s.checkpoint),
        i32(s.finished),
        i32(s.item),
        i32(s.events),
        i32(s.rivals[0]),
        i32(s.hop),
        i32(s.switches),
        i32(s.pickup),
        i32(s.rivals[1]),
        i32(s.rivals[2]),
        i32(s.rivals[3]),
        i32(s.rivals[4]),
        i32(s.rivals[5]),
        i32(s.rivals[6]),
        i32(math.floor(position[1] * 256)),
    }
    return u32(uintptr(&inspection))
}

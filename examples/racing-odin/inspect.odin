package main

// Optional development replay state; independent of the console ABI.
inspection: [10]i32
@(export) game_inspect :: proc "c" () -> u32 {
    inspection={i32(s.distance),i32(s.x),i32(s.speed),i32(s.charge),i32(s.elapsed),i32(s.hits),i32(s.offroad),i32(s.boosts),i32(s.finished),i32(s.ticks)}
    return u32(uintptr(&inspection))
}

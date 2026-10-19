package main

// Optional development replay state; independent of the console ABI.
inspection: [10]i32
@(export) game_inspect :: proc "c" () -> u32 {
    flags := i32(s.quest) | i32(s.herb)<<1 | i32(s.won)<<2 | i32(s.complete)<<3 | i32(s.defeated)<<4
    inspection = {i32(s.x),i32(s.y),i32(s.hp),i32(s.potions),i32(s.enemy),i32(s.choice),i32(s.mode),flags,i32(s.steps),i32(s.ticks)}
    return u32(uintptr(&inspection))
}

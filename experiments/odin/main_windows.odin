package main

import "core:fmt"

main :: proc() {
    game_init()
    for tick in 0 ..< 120 {
        buttons: u32
        if tick < 60 {

            buttons = 2
        }
        if tick == 60 {

            buttons = 16
        }
        game_update(1.0 / 60.0, buttons)
    }
    fmt.printf(
        "x=%.9f y=%.9f ticks=%d sounds=%d\n",
        game_x(),
        game_y(),
        game_ticks(),
        game_sounds(),
    )
}

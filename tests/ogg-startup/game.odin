package main

import audio "sdk:audio"
import byt "sdk:bytorio"

updates: u32

init :: proc() {
    updates = 0
    audio.bus_gain(audio.master(), f32(1))
}

update :: proc(_dt: f64) {
    updates += 1
    if updates == 12 {
        music := audio.ogg_stream(1)
        audio.play_stream(audio.voice(0), music, {gain = f32(0.5)})
    }
}

draw :: proc() {
    byt.clear(byt.rgb(20, 28, 44))
}

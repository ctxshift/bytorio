package main

import audio "sdk:audio"
import byt "sdk:bytorio"

updates: u32

init :: proc() {
    updates = 0
    music := audio.ogg_stream(1, {loop = true, loop_start = 431, loop_end = 4199})
    audio.play_stream(audio.voice(0), music, {gain = f32(0.5)})
}

update :: proc(_dt: f64) {
    updates += 1
    audio.gain(audio.voice(0), f32(0.5))
}

draw :: proc() {
    byt.clear(byt.rgb(20, 28, 44))
}

@(export)
admission_updates :: proc "contextless" () -> u32 {
    return updates
}

package main

import audio "sdk:audio"
import byt "sdk:bytorio"
import data "sdk:data"

init :: proc() {
    values := [4]i16{0, 4096, 0, -4096}
    pcm := data.from_i16(values[:], 1)
    defer data.free_pcm(&pcm)
    sample := audio.sample({frames = 4, channels = 1, rate = 8000}, pcm)
    audio.play_sample(audio.voice(0), sample, {loop = true, loop_end = 4})
}

update :: proc(_dt: f64) {
    audio.gain(audio.voice(0), 0.1)
}

draw :: proc() {
    byt.clear(byt.rgb(20, 28, 44))
}

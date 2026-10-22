package main

import audio "sdk:audio"
import byt "sdk:bytorio"

init :: proc() {
    music := audio.ogg_stream(1, {loop = true, loop_start = 431, loop_end = 4199})
    effect := audio.ogg_stream(1)
    short_loop := audio.ogg_stream(1, {loop = true, loop_start = 431, loop_end = 432})
    audio.play_stream(audio.voice(0), music, {gain = f32(0.5)})
    audio.play_stream(audio.voice(1), effect, {gain = f32(0.25)})
    audio.play_stream(audio.voice(2), short_loop, {gain = f32(0.125)})
}
update :: proc(_dt: f64) {  }
draw :: proc() { byt.clear(byt.rgb(20, 28, 44)) }

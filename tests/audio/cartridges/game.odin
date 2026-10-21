package main

import audio "sdk:audio"
import byt "sdk:bytorio"
import data "sdk:data"

init :: proc() {
    values := [8]i16{0, 8192, 16384, 24576, 32767, 24576, 16384, 8192}
    pcm := data.from_i16(values[:], 1)
    defer data.free_pcm(&pcm)
    sample := audio.sample({frames = 8, channels = 1, rate = 24000}, pcm)
    bus := audio.bus({gain = f32(0.5)})
    v := audio.voice(0)
    audio.play_sample(
        v,
        sample,
        {bus = bus, loop = true, loop_start = 2, loop_end = 8, gain = f32(0.5), pan = -0.25},
    )
    audio.play_sample(audio.voice(1), sample, {at = u64(24), gain = f32(0.25), pan = 0.5})
    audio.gain(v, 1, 64, 32)
    audio.pan(v, 0.5, 128, 32)
    audio.bus_gain(bus, 0.25, 192, 16)
    audio.release(v, 20, 300)
    audio.play_sample(audio.voice(3), sample, {loop = true, loop_end = 8, gain = f32(0.02)})
    stream := audio.stream()
    stereo := data.pcm(128, 2)
    defer data.free_pcm(&stereo)
    for i in 0 ..< 128 { stereo.samples[i * 2] = 0.2; stereo.samples[i * 2 + 1] = -0.2 }
    audio.write_stream(stream, 512, stereo)
    audio.play_stream(audio.voice(2), stream, {at = u64(480), gain = f32(0.5)})
    audio.stop(audio.voice(2), 640)
    audio.write_stream(stream, 800, {frames = 64, channels = 2, samples = stereo.samples[:128]})
    audio.play_stream(audio.voice(2), stream, {at = u64(768), gain = f32(0.5)})
    audio.stop(audio.voice(2), 880)
    // Reusing guest staging memory cannot alter either accepted resource or voice.
    for &value in pcm.samples { value = 0 }
}
update :: proc(_dt: f64) {
    status := audio.status()
    _, count := audio.completions()
    byt.debug_position(f64(status.completed), f64(count))
}
draw :: proc() {
    byt.clear(byt.rgb(20, 28, 44))
    byt.rect(24, 40, 272, 48, byt.rgb(64, 170, 205))
    byt.text("PCM MIXER: 4 VOICES + STREAM", 24, 20, byt.rgb(240, 240, 240))
}

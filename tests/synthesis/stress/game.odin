package main

import audio "sdk:audio"
import console "sdk:console"
import data "sdk:data"

init :: proc() {
    pcm := data.pcm(32, 1)
    defer data.free_pcm(&pcm)
    for &value, i in pcm.samples { value = f32(i) / 16 - 1 }
    wave := audio.wavetable({32, 1}, pcm)
    nodes: [16]audio.Node
    nodes[0] = {
        kind   = .Wavetable,
        source = wave,
    }
    for i in 1 ..< 14 {
        nodes[i] = {
            kind      = .Filter,
            input     = u32(i - 1),
            cutoff_hz = 6000,
            resonance = 0.4,
        }
    }
    nodes[14] = {
        kind  = .Gain,
        input = 13,
        gain  = 0.03,
    }
    nodes[15] = {
        kind  = .Output,
        input = 14,
    }
    instrument := audio.instrument(nodes[:])
    buses: [8]audio.Bus
    buses[0] = audio.master()
    for i in 1 ..< len(buses) { buses[i] = audio.bus() }
    fx := [8]audio.Node {
        {kind = .Input},
        {kind = .Filter, input = 0, cutoff_hz = 6000, resonance = 0.4},
        {kind = .Delay, input = 1, max_delay_frames = 256, delay_frames = 128, feedback = 0.5},
        {kind = .Gain, input = 2},
        {kind = .Gain, input = 3},
        {kind = .Gain, input = 4},
        {kind = .Gain, input = 5},
        {kind = .Output, input = 6},
    }
    for bus in buses { audio.effects(bus, fx[:]) }
    for i in 0 ..< 16 { audio.note_on(audio.voice(u32(i)), instrument, f32(220 + i * 11), {bus = buses[i % 8]}) }
    for &value in pcm.samples { value *= -1 }
    audio.edit_wavetable(wave, 0, pcm, 512)
    for i in 0 ..< 16 { audio.node_control(audio.voice(u32(i)), instrument, 0, .Frequency, 660, 1024, 128) }
    for bus in buses { audio.effect_control(bus, 1, .Cutoff, 1200, 2048, 512) }
}
update :: proc(dt: f64) {
    status := audio.status()
    _, count := audio.completions()
    console.debug_position(f64(status.completed), f64(count))
}
draw :: proc() {
    console.clear(console.rgb(20, 28, 44))
    console.text("DSP LOAD: 16 VOICES / 8 BUSES / 320 NODES", 8, 20, console.rgb(240, 240, 240))
}

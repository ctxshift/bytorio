package main

import audio "sdk:audio"
import byt "sdk:bytorio"
import data "sdk:data"

tone: audio.Instrument
tone_pitch: f32 = 440
tone_cutoff: f32 = 1200
tone_wave: f32 = 0.25

init :: proc() {
    pcm := data.pcm(64, 1)
    defer data.free_pcm(&pcm)
    for &value, i in pcm.samples {
        phase := f32(i % 32) / 32
        value = phase * 2 - 1 if i < 32 else (1 if i % 32 < 16 else -1)
    }
    wave := audio.wavetable({32, 2}, pcm)
    notes := []audio.Node {
        {kind = .Wavetable, source = wave},
        {kind = .Wavetable, source = wave, frequency_hz = 110},
        {kind = .LFO, frequency_hz = 5},
        {kind = .ADSR, attack_frames = 16, decay_frames = 32, sustain = 0.5, release_frames = 64},
        {
            kind            = .Wavetable,
            source          = wave,
            wave            = 0.25,
            frequency_input = 1,
            fm_depth_hz     = 80,
            phase_input     = 2,
            pm_depth_cycles = 0.03,
        },
        {kind = .Mix, input = 0, other = 4, gain = 0.4, secondary_gain = 0.6},
        {kind = .Gain, input = 5, gain = 0, gain_input = 3, depth = 0.2},
        {kind = .Filter, input = 6, cutoff_hz = 1200, resonance = 0.2},
        {
            kind             = .Delay,
            input            = 7,
            max_delay_frames = 128,
            delay_frames     = 64,
            feedback         = 0.25,
            wet              = 0.35,
        },
        {kind = .Pan, input = 8, pan = -0.2},
        {kind = .Output, input = 9},
    }
    instrument := audio.instrument(notes)
    tone = instrument
    noise := audio.instrument([]audio.Node {
        {kind = .Noise, seed = 1234567},
        {kind = .ADSR, attack_frames = 4, decay_frames = 8, sustain = 0.25, release_frames = 32},
        {kind = .Gain, input = 0, gain = 0, gain_input = 1, depth = 0.08},
        {kind = .Filter, input = 2, cutoff_hz = 5000, resonance = 0.1, filter_mode = .Highpass},
        {kind = .Output, input = 3},
    })
    bus := audio.bus({gain = 0.8})
    audio.effects(bus, []audio.Node {
        {kind = .Input},
        {
            kind             = .Delay,
            input            = 0,
            max_delay_frames = 256,
            delay_frames     = 96,
            feedback         = 0.3,
            wet              = 0.25,
        },
        {kind = .Filter, input = 1, cutoff_hz = 6000},
        {kind = .Output, input = 2},
    })
    v := audio.voice(0)
    audio.note_on(v, instrument, 440, {bus = bus, velocity = 0.8})
    audio.note_on(audio.voice(1), noise, 440, {bus = bus, at = 64})
    audio.node_control(v, instrument, 4, .Wave, 1, 128, 64)
    audio.node_control(v, instrument, 7, .Cutoff, 2400, 256, 128)
    audio.effect_control(bus, 1, .Feedback, 0.1, 320, 32)
    patch := data.pcm(8, 1)
    defer data.free_pcm(&patch)
    for &value in patch.samples { value = 0.25 }
    audio.edit_wavetable(wave, 4, patch, 512)
    audio.note_off(audio.voice(1), 640)
    audio.note_off(v, 1024)
    // A sustained third note proves independent state and producer-stall survival.
    audio.note_on(audio.voice(2), instrument, 220, {at = 1200, velocity = 0.3})
    audio.node_control(audio.voice(2), instrument, 8, .Wet, 0.8, 1600, 128)
    sample_pcm := data.pcm(8, 1)
    defer data.free_pcm(&sample_pcm)
    copy(sample_pcm.samples, []f32{0, 0.25, 0.5, 0.75, 1, 0.75, 0.5, 0.25})
    sample := audio.sample({8, 1, 24000}, sample_pcm)
    sample_instrument := audio.instrument([]audio.Node {
        {kind = .Sample, source = sample, loop = true, loop_end = 8},
        {kind = .Gain, input = 0, gain = 0.05},
        {kind = .Pan, input = 1, pan = 0.4},
        {kind = .Output, input = 2},
    })
    audio.note_on(audio.voice(3), sample_instrument, 440, {at = 96})
    sample_patch := data.pcm(1, 1)
    defer data.free_pcm(&sample_patch)
    sample_patch.samples[0] = -0.5
    audio.edit_sample(sample, 0, sample_patch, 800)
    audio.note_off(audio.voice(3), 1800)
    cancelled_pcm := data.pcm(2, 1)
    defer data.free_pcm(&cancelled_pcm)
    for &value in cancelled_pcm.samples { value = 0.5 }
    cancelled := audio.sample({2, 1, 48000}, cancelled_pcm)
    audio.edit_sample(cancelled, 0, cancelled_pcm)
    audio.play_sample(audio.voice(4), cancelled, {at = 2000})
    audio.destroy(cancelled)
    for &value in pcm.samples { value = 0 }
}
update :: proc(dt: f64) {
    if byt.pressed(.Left) { tone_pitch = max(110, tone_pitch / 2) }
    if byt.pressed(.Right) { tone_pitch = min(1760, tone_pitch * 2) }
    if byt.pressed(.Up) { tone_cutoff = min(12000, tone_cutoff + 400) }
    if byt.pressed(.Down) { tone_cutoff = max(200, tone_cutoff - 400) }
    if byt.pressed(.Action) { tone_wave = 1 - tone_wave }
    v := audio.voice(2)
    if byt.pressed(.Left) || byt.pressed(.Right) {
        audio.node_control(v, tone, 0, .Frequency, tone_pitch, audio.ASAP, 64)
        audio.node_control(v, tone, 4, .Frequency, tone_pitch, audio.ASAP, 64)
    }
    if byt.pressed(.Up) ||
       byt.pressed(.Down) { audio.node_control(v, tone, 7, .Cutoff, tone_cutoff, audio.ASAP, 64) }
    if byt.pressed(.Action) { audio.node_control(v, tone, 4, .Wave, tone_wave, audio.ASAP, 64) }
    status := audio.status()
    _, count := audio.completions()
    byt.debug_position(f64(status.completed), f64(count))
}
draw :: proc() {
    byt.clear(byt.rgb(20, 28, 44))
    byt.text("SYNTH: FM / ENVELOPE / FILTER / DELAY", 12, 20, byt.rgb(240, 240, 240))
    byt.rect(24, 48, 272, 40, byt.rgb(70, 180, 150))
    byt.rect(24, 92, int(tone_pitch / 8), 6, byt.rgb(240, 200, 80))
    byt.text("LEFT/RIGHT PITCH  UP/DOWN FILTER", 12, 110, byt.rgb(240, 240, 240))
    byt.text("SPACE: MORPH WAVE", 12, 126, byt.rgb(240, 240, 240))
}

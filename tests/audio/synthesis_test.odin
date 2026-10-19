package audio_test

import mixer "../../runtime/odin/audio"
import w "../../runtime/odin/resource_protocol"
import r "../../runtime/odin/resources"
import audio "../../sdk/odin/audio"
import data "../../sdk/odin/data"
import t "../../sdk/odin/resource"
import "base:runtime"
import "core:math"
import "core:sync"
import "core:testing"

@(test)
destroy_live_source_cancels_future_pcm :: proc(test: ^testing.T) {
    sync.mutex_lock(&sdk_mutex)
    defer sync.mutex_unlock(&sdk_mutex)
    registry: r.Registry
    defer r.close(&registry)
    testing.expect(test, r.reset(&registry, 111) && t.configure(111))
    t.begin(0)
    pcm := data.pcm(2, 1)
    defer data.free_pcm(&pcm)
    for &value in pcm.samples { value = 0.5 }
    source := audio.sample({2, 1, w.audioRate}, pcm)
    audio.edit_sample(source, 0, pcm)
    audio.play_sample(audio.voice(0), source, {at = 160})
    audio.destroy(source)
    testing.expect(test, commit(&registry), registry.error)
    testing.expect(test, t.ack(1))
    registry.audio.lead_remaining = 0
    output: [512]f32
    mixer.render(registry.audio, output[:])
    for value in output { testing.expect_value(test, value, f32(0)) }
    mixer.reclaim(registry.audio)
    testing.expect_value(test, registry.audio.completed, u64(1))
    testing.expect_value(test, registry.audio.completions[0].reason, u32(w.audioReasonCancelled))
    testing.expect_value(test, registry.audio.completions[0].frame, u64(160))
    testing.expect_value(test, registry.audio.used, u64(0))
}

@(test)
history_pressure_preserves_active_voice :: proc(test: ^testing.T) {
    sync.mutex_lock(&sdk_mutex)
    defer sync.mutex_unlock(&sdk_mutex)
    registry: r.Registry
    defer r.close(&registry)
    testing.expect(test, r.reset(&registry, 110) && t.configure(110))
    t.begin(0)
    instrument := audio.instrument([]audio.Node {
        {kind = .Noise},
        {kind = .Delay, input = 0, max_delay_frames = w.maxDelayFrames},
        {kind = .Output, input = 1},
    })
    audio.note_on(audio.voice(0), instrument, 440)
    testing.expect(test, commit(&registry), registry.error)
    testing.expect(test, t.ack(1))
    registry.audio.lead_remaining = 0
    output: [256]f32
    mixer.render(registry.audio, output[:])
    retained := registry.audio.used
    cursor := registry.audio.voices[0].synth.states[1].cursor
    t.begin(1)
    for i in 1 ..< w.maxVoices {
        audio.note_on(audio.voice(u32(i)), instrument, 440)
    }
    testing.expect(test, !commit(&registry))
    testing.expect_value(test, registry.error, "note DSP history budget exhausted")
    testing.expect_value(test, registry.audio.used, retained)
    testing.expect_value(test, registry.audio.voices[0].kind, u32(3))
    testing.expect(test, t.ack(2))
    mixer.render(registry.audio, output[:])
    testing.expect(
        test,
        registry.audio.voices[0].synth.states[1].cursor > cursor,
        "failed admission leaves the active graph running",
    )
}

@(test)
envelope_morph_and_scheduled_edit_reference :: proc(test: ^testing.T) {
    sync.mutex_lock(&sdk_mutex)
    defer sync.mutex_unlock(&sdk_mutex)
    registry: r.Registry
    defer r.close(&registry)
    testing.expect(test, r.reset(&registry, 61) && t.configure(61))
    t.begin(0)
    pcm := data.pcm(64, 1)
    defer data.free_pcm(&pcm)
    for &value, i in pcm.samples { value = f32(i) / 16 - 1 if i < 32 else 0.5 }
    wave := audio.wavetable({32, 2}, pcm)
    instrument := audio.instrument([]audio.Node {
        {kind = .Wavetable, source = wave, frequency_hz = 1500, wave = 0.5},
        {kind = .ADSR, attack_frames = 4, decay_frames = 4, sustain = 0.5, release_frames = 4},
        {kind = .Gain, input = 0, gain = 0, gain_input = 1, depth = 1},
        {kind = .Output, input = 2},
    })
    v := audio.voice(0)
    audio.note_on(v, instrument, 440)
    audio.node_control(v, instrument, 0, .Wave, 1, 8)
    patch := data.pcm(4, 1)
    defer data.free_pcm(&patch)
    for &value in patch.samples { value = -0.5 }
    audio.edit_wavetable(wave, 44, patch, 12)
    audio.note_off(v, 16)
    testing.expect(test, commit(&registry), registry.error)
    testing.expect(test, t.ack(1))
    registry.audio.lead_remaining = 0
    output: [64]f32
    mixer.render(registry.audio, output[:])
    for n in 0 ..< 32 {
        envelope := f32(0)
        if n <
           4 { envelope = f32(n) / 4 } else if n < 8 { envelope = 1 - f32(n - 4) / 8 } else if n < 16 { envelope = 0.5 } else if n < 20 { envelope = 0.5 - f32(n - 16) / 8 }
        oscillator := -0.25 + f32(n) / 32 if n < 8 else -0.5 if n >= 12 && n < 16 else 0.5
        expected := oscillator * envelope
        testing.expect(
            test,
            math.abs(output[n * 2] - expected) < 1e-6,
            "independent ADSR/morph/edit reference",
        )
        testing.expect_value(test, output[n * 2], output[n * 2 + 1])
    }
    mixer.reclaim(registry.audio)
    testing.expect_value(test, registry.audio.completed, u64(1))
    testing.expect_value(test, registry.audio.completions[0].frame, u64(20))
    testing.expect_value(test, registry.audio.used, u64(2048))
}

@(test)
typed_graphs_and_source_lifetimes :: proc(test: ^testing.T) {
    sync.mutex_lock(&sdk_mutex)
    defer sync.mutex_unlock(&sdk_mutex)
    registry: r.Registry
    defer r.close(&registry)
    for kind in 0 ..< 7 {
        session := u32(70 + kind)
        testing.expect(test, r.reset(&registry, session) && t.configure(session))
        t.begin(0)
        nodes := [3]audio.Node {
            {kind = .Noise},
            {kind = .Gain, input = 0},
            {kind = .Output, input = 1},
        }
        switch kind {
        case 0:
            nodes[1] = {
                kind  = .Gain,
                input = 2,
            }
        case 1:
            nodes[0] = {
                kind = .LFO,
            }
        case 2:
            nodes[1] = {
                kind             = .Delay,
                input            = 0,
                max_delay_frames = w.maxDelayFrames + 1,
            }
        case 3:
            nodes[1] = {
                kind      = .Filter,
                input     = 0,
                resonance = 1,
            }
        case 4:
            nodes[0] = {
                kind = .Wavetable,
            }
        case 5:
            nodes[0] = {
                kind = .Noise,
                seed = 0,
            }
        case 6:
            nodes[1] = {
                kind             = .Delay,
                input            = 0,
                max_delay_frames = 16,
                delay_frames     = 0,
            }
        }
        _ = audio.instrument(nodes[:])
        testing.expect(
            test,
            !commit(&registry),
            "cycle, control/audio mismatch, capacity and bad source rejected",
        )
        testing.expect_value(test, registry.bytes, 0)
        testing.expect(
            test,
            registry.audio == nil,
            "failed synthesis creation rolls back the engine",
        )
        testing.expect(test, t.ack(1))
    }
    testing.expect(test, r.reset(&registry, 80) && t.configure(80))
    t.begin(0)
    pcm := data.pcm(32, 1)
    defer data.free_pcm(&pcm)
    wave := audio.wavetable({32, 1}, pcm)
    _ = audio.instrument(
        []audio.Node{{kind = .Wavetable, source = wave}, {kind = .Output, input = 0}},
    )
    audio.destroy_wavetable(wave)
    testing.expect(test, !commit(&registry), "instrument source must outlive its definition")
    testing.expect(test, registry.audio == nil)
    testing.expect(test, t.ack(1))
}

@(test)
full_graph_workload_and_reclamation :: proc(test: ^testing.T) {
    sync.mutex_lock(&sdk_mutex)
    defer sync.mutex_unlock(&sdk_mutex)
    registry: r.Registry
    defer r.close(&registry)
    testing.expect(test, r.reset(&registry, 90) && t.configure(90))
    t.begin(0)
    nodes: [w.maxInstrumentNodes]audio.Node
    nodes[0] = {
        kind = .Noise,
        seed = 1234567,
    }
    for i in 1 ..< len(nodes) - 1 {nodes[i] = {
            kind  = .Gain,
            input = u32(i - 1),
            gain  = 0.5,
        }}
    nodes[len(nodes) - 1] = {
        kind  = .Output,
        input = u32(len(nodes) - 2),
    }
    instrument := audio.instrument(nodes[:])
    buses: [w.maxBuses]audio.Bus
    buses[0] = audio.master()
    for i in 1 ..< len(buses) { buses[i] = audio.bus() }
    fx := [w.maxBusNodes]audio.Node {
        {kind = .Input},
        {kind = .Filter, input = 0},
        {kind = .Delay, input = 1, max_delay_frames = 16, feedback = 0.5},
        {kind = .Gain, input = 2},
        {kind = .Gain, input = 3},
        {kind = .Gain, input = 4},
        {kind = .Gain, input = 5},
        {kind = .Output, input = 6},
    }
    for bus in buses { audio.effects(bus, fx[:]) }
    for i in 0 ..< w.maxVoices { audio.note_on(audio.voice(u32(i)), instrument, 440, {bus = buses[i % len(buses)]}) }
    testing.expect(test, commit(&registry), registry.error)
    testing.expect(test, t.ack(1))
    registry.audio.lead_remaining = 0
    output: [2048]f32
    allocator := context.allocator
    context.allocator = runtime.nil_allocator()
    mixer.render(registry.audio, output[:])
    context.allocator = allocator
    for value in output { testing.expect(test, !math.is_nan(value) && !math.is_inf(value) && math.abs(value) <= 1) }
    t.begin(1)
    for bus in buses { audio.effects(bus, nil) }
    audio.destroy_instrument(instrument)
    for i in 1 ..< len(buses) { audio.destroy_bus(buses[i]) }
    testing.expect(test, commit(&registry), registry.error)
    testing.expect(test, t.ack(2))
    mixer.render(registry.audio, output[:])
    mixer.reclaim(registry.audio)
    testing.expect_value(test, registry.audio.used, u64(0))
    testing.expect_value(test, registry.audio.completed, u64(w.maxVoices))
}

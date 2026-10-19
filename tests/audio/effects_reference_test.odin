package audio_test

import mixer "../../runtime/odin/audio"
import w "../../runtime/odin/resource_protocol"
import r "../../runtime/odin/resources"
import audio "../../sdk/odin/audio"
import data "../../sdk/odin/data"
import t "../../sdk/odin/resource"
import "core:fmt"
import "core:math"
import "core:sync"
import "core:testing"

NOISE_REFERENCE_WORDS :: [8]u32 {
    42034982,
    3805524628,
    78537300,
    3564389094,
    3644666546,
    2449665511,
    947072312,
    3881073042,
}

@(test)
sample_delay_filter_and_noise_references :: proc(test: ^testing.T) {
    sync.mutex_lock(&sdk_mutex)
    defer sync.mutex_unlock(&sdk_mutex)
    registry: r.Registry
    noise_reference := NOISE_REFERENCE_WORDS
    defer r.close(&registry)
    for mode in 0 ..< 4 {
        session := u32(100 + mode)
        testing.expect(test, r.reset(&registry, session) && t.configure(session))
        t.begin(0)
        pcm := data.pcm(8, 1)
        pcm.samples[0] = 1
        if mode == 3 { copy(pcm.samples, []f32{0, 0.25, 0.5, 0.75, 1, 0.75, 0.5, 0.25}) }
        source := audio.sample({8, 1, w.audioRate if mode != 3 else w.audioRate / 2}, pcm)
        nodes: [3]audio.Node
        nodes[0] = {
            kind   = .Sample,
            source = source,
        }
        nodes[1] = {
            kind  = .Gain,
            input = 0,
        }
        if mode == 0 {nodes[1] = {
                kind             = .Delay,
                input            = 0,
                max_delay_frames = 16,
                delay_frames     = 3,
                feedback         = 0.5,
                wet              = 1,
            }}
        if mode == 1 {nodes[1] = {
                kind      = .Filter,
                input     = 0,
                cutoff_hz = 1000,
            }}
        if mode == 2 {nodes[0] = {
                kind = .Noise,
                seed = 1234567,
            }}
        if mode == 3 {nodes[0] = {
                kind     = .Sample,
                source   = source,
                loop     = true,
                loop_end = 8,
            }}
        nodes[2] = {
            kind  = .Output,
            input = 1,
        }
        instrument := audio.instrument(nodes[:])
        audio.note_on(audio.voice(0), instrument, 440)
        if mode == 3 {
            patch := data.pcm(1, 1)
            patch.samples[0] = -0.5
            audio.edit_sample(source, 0, patch, 18)
            data.free_pcm(&patch)
        }
        data.free_pcm(&pcm)
        testing.expect(test, commit(&registry), registry.error)
        testing.expect(test, t.ack(1))
        registry.audio.lead_remaining = 0
        output: [64]f32
        mixer.render(registry.audio, output[:])
        integrator: [2]f64
        // An independent trigonometric SVF reference checks the fixed polynomial
        // implementation at 1 kHz, where their coefficient error is below 1e-8.
        g := math.tan(math.PI * 1000 / w.audioRate)
        for n in 0 ..< 32 {
            expected := f64(0)
            switch mode {
            case 0:
                if n >= 3 && n % 3 == 0 { expected = math.pow(0.5, f64(n / 3 - 1)) }
            case 1:
                input := f64(1) if n == 0 else 0
                v3 := input - integrator[1]
                v1 := (integrator[0] + g * v3) / (1 + g * (g + 2))
                expected = integrator[1] + g * v1
                integrator = {2 * v1 - integrator[0], 2 * expected - integrator[1]}
            case 2:
                if n >= len(NOISE_REFERENCE_WORDS) { continue }
                expected = f64(noise_reference[n]) / 2147483648.0 - 1
            case 3:
                reference := [8]f64{0, 0.25, 0.5, 0.75, 1, 0.75, 0.5, 0.25}
                if n >= 18 { reference[0] = -0.5 }
                first := (n / 2) % len(reference)
                expected = reference[first]
                if n % 2 ==
                   1 { expected = (expected + reference[(first + 1) % len(reference)]) / 2 }
            }
            if math.abs(f64(output[n * 2]) - expected) >= 1e-6 {
                testing.expect(
                    test,
                    false,
                    fmt.tprintf(
                        "mode %d frame %d: actual %.8f expected %.8f",
                        mode,
                        n,
                        output[n * 2],
                        expected,
                    ),
                )
            }
            testing.expect_value(test, output[n * 2], output[n * 2 + 1])
        }
    }
}

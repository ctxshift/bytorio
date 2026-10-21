--!strict
local byt = require("@bytorio")
local audio, data = byt.audio, byt.data
local tone: byt.Instrument? = nil
local tonePitch, toneCutoff, toneWave = 440, 1200, 0.25
return {
    init = function()
        local pcm = data.pcm(64, 1)
        for i = 0, 63 do
            local phase = (i % 32) / 32
            local value = if i < 32 then phase * 2 - 1 else (if i % 32 < 16 then 1 else -1)
            buffer.writef32(pcm.samples, i * 4, value)
        end
        local wave = audio.wavetable({ frames = 32, waves = 2 }, pcm)
        local instrument = audio.instrument({
            { kind = "wavetable", source = wave },
            { kind = "wavetable", source = wave, frequency_hz = 110 },
            { kind = "lfo", frequency_hz = 5 },
            {
                kind = "adsr",
                attack_frames = 16,
                decay_frames = 32,
                sustain = 0.5,
                release_frames = 64,
            },
            {
                kind = "wavetable",
                source = wave,
                wave = 0.25,
                frequency_input = 1,
                fm_depth_hz = 80,
                phase_input = 2,
                pm_depth_cycles = 0.03,
            },
            { kind = "mix", input = 0, other = 4, gain = 0.4, secondary_gain = 0.6 },
            { kind = "gain", input = 5, gain = 0, gain_input = 3, depth = 0.2 },
            { kind = "filter", input = 6, cutoff_hz = 1200, resonance = 0.2 },
            {
                kind = "delay",
                input = 7,
                max_delay_frames = 128,
                delay_frames = 64,
                feedback = 0.25,
                wet = 0.35,
            },
            { kind = "pan", input = 8, pan = -0.2 },
            { kind = "output", input = 9 },
        })
        tone = instrument
        local noise = audio.instrument({
            { kind = "noise", seed = 1234567 },
            {
                kind = "adsr",
                attack_frames = 4,
                decay_frames = 8,
                sustain = 0.25,
                release_frames = 32,
            },
            { kind = "gain", input = 0, gain = 0, gain_input = 1, depth = 0.08 },
            {
                kind = "filter",
                input = 2,
                cutoff_hz = 5000,
                resonance = 0.1,
                filter_mode = "highpass",
            },
            { kind = "output", input = 3 },
        })
        local bus = audio.bus({ gain = 0.8 })
        audio.effects(bus, {
            { kind = "input" },
            {
                kind = "delay",
                input = 0,
                max_delay_frames = 256,
                delay_frames = 96,
                feedback = 0.3,
                wet = 0.25,
            },
            { kind = "filter", input = 1, cutoff_hz = 6000 },
            { kind = "output", input = 2 },
        })
        local v = audio.voice(0)
        audio.note_on(v, instrument, 440, { bus = bus, velocity = 0.8 })
        audio.note_on(audio.voice(1), noise, 440, { bus = bus, at = 64 })
        audio.node_control(v, instrument, 4, "wave", 1, 128, 64)
        audio.node_control(v, instrument, 7, "cutoff", 2400, 256, 128)
        audio.effect_control(bus, 1, "feedback", 0.1, 320, 32)
        local patch = data.pcm(8, 1)
        for i = 0, 7 do
            buffer.writef32(patch.samples, i * 4, 0.25)
        end
        audio.edit_wavetable(wave, 4, patch, 512)
        audio.note_off(audio.voice(1), 640)
        audio.note_off(v, 1024)
        audio.note_on(audio.voice(2), instrument, 220, { at = 1200, velocity = 0.3 })
        audio.node_control(audio.voice(2), instrument, 8, "wet", 0.8, 1600, 128)
        local samplePcm = data.pcm(8, 1)
        for i, value in { 0, 0.25, 0.5, 0.75, 1, 0.75, 0.5, 0.25 } do
            buffer.writef32(samplePcm.samples, (i - 1) * 4, value)
        end
        local sample = audio.sample({ frames = 8, channels = 1, rate = 24000 }, samplePcm)
        local sampleInstrument = audio.instrument({
            { kind = "sample", source = sample, loop = true, loop_end = 8 },
            { kind = "gain", input = 0, gain = 0.05 },
            { kind = "pan", input = 1, pan = 0.4 },
            { kind = "output", input = 2 },
        })
        audio.note_on(audio.voice(3), sampleInstrument, 440, { at = 96 })
        local samplePatch = data.pcm(1, 1)
        buffer.writef32(samplePatch.samples, 0, -0.5)
        audio.edit_sample(sample, 0, samplePatch, 800)
        audio.note_off(audio.voice(3), 1800)
        local cancelledPcm = data.pcm(2, 1)
        buffer.writef32(cancelledPcm.samples, 0, 0.5)
        buffer.writef32(cancelledPcm.samples, 4, 0.5)
        local cancelled = audio.sample({ frames = 2, channels = 1, rate = 48000 }, cancelledPcm)
        audio.edit_sample(cancelled, 0, cancelledPcm)
        audio.play_sample(audio.voice(4), cancelled, { at = 2000 })
        audio.destroy(cancelled)
        buffer.fill(pcm.samples, 0, 0)
    end,
    update = function(_dt: number)
        if byt.pressed("left") then
            tonePitch = math.max(110, tonePitch / 2)
        end
        if byt.pressed("right") then
            tonePitch = math.min(1760, tonePitch * 2)
        end
        if byt.pressed("up") then
            toneCutoff = math.min(12000, toneCutoff + 400)
        end
        if byt.pressed("down") then
            toneCutoff = math.max(200, toneCutoff - 400)
        end
        if byt.pressed("action") then
            toneWave = 1 - toneWave
        end
        local instrument = tone
        if instrument then
            local v = audio.voice(2)
            if byt.pressed("left") or byt.pressed("right") then
                audio.node_control(v, instrument, 0, "frequency", tonePitch, nil, 64)
                audio.node_control(v, instrument, 4, "frequency", tonePitch, nil, 64)
            end
            if byt.pressed("up") or byt.pressed("down") then
                audio.node_control(v, instrument, 7, "cutoff", toneCutoff, nil, 64)
            end
            if byt.pressed("action") then
                audio.node_control(v, instrument, 4, "wave", toneWave, nil, 64)
            end
        end
        local status = audio.status()
        byt.debug_position(status.completed, #audio.completions())
    end,
    draw = function()
        byt.clear(byt.rgb(20, 28, 44))
        byt.text("SYNTH: FM / ENVELOPE / FILTER / DELAY", 12, 20, byt.rgb(240, 240, 240))
        byt.rect(24, 48, 272, 40, byt.rgb(70, 180, 150))
        byt.rect(24, 92, math.floor(tonePitch / 8), 6, byt.rgb(240, 200, 80))
        byt.text("LEFT/RIGHT PITCH  UP/DOWN FILTER", 12, 110, byt.rgb(240, 240, 240))
        byt.text("SPACE: MORPH WAVE", 12, 126, byt.rgb(240, 240, 240))
    end,
}

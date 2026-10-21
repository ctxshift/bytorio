--!strict
local byt = require("@bytorio")
local audio, data = byt.audio, byt.data
return {
    init = function()
        local pcm = data.pcm(32, 1)
        for i = 0, 31 do
            buffer.writef32(pcm.samples, i * 4, i / 16 - 1)
        end
        local wave = audio.wavetable({ frames = 32, waves = 1 }, pcm)
        local nodes: { byt.SynthNode } = { { kind = "wavetable", source = wave } }
        for i = 1, 13 do
            local filter: byt.SynthNode =
                { kind = "filter", input = i - 1, cutoff_hz = 6000, resonance = 0.4 }
            table.insert(nodes, filter)
        end
        local finalGain: byt.SynthNode = { kind = "gain", input = 13, gain = 0.03 }
        table.insert(nodes, finalGain)
        local output: byt.SynthNode = { kind = "output", input = 14 }
        table.insert(nodes, output)
        local instrument = audio.instrument(nodes)
        local buses = { audio.master() }
        for _ = 1, 7 do
            table.insert(buses, audio.bus())
        end
        local fx: { byt.SynthNode } = {
            { kind = "input" },
            { kind = "filter", input = 0, cutoff_hz = 6000, resonance = 0.4 },
            {
                kind = "delay",
                input = 1,
                max_delay_frames = 256,
                delay_frames = 128,
                feedback = 0.5,
            },
            { kind = "gain", input = 2 },
            { kind = "gain", input = 3 },
            { kind = "gain", input = 4 },
            { kind = "gain", input = 5 },
            { kind = "output", input = 6 },
        }
        for _, bus in buses do
            audio.effects(bus, fx)
        end
        for i = 0, 15 do
            audio.note_on(audio.voice(i), instrument, 220 + i * 11, { bus = buses[i % 8 + 1] })
        end
        for i = 0, 31 do
            buffer.writef32(pcm.samples, i * 4, -(i / 16 - 1))
        end
        audio.edit_wavetable(wave, 0, pcm, 512)
        for i = 0, 15 do
            audio.node_control(audio.voice(i), instrument, 0, "frequency", 660, 1024, 128)
        end
        for _, bus in buses do
            audio.effect_control(bus, 1, "cutoff", 1200, 2048, 512)
        end
    end,
    update = function(_dt: number)
        local status = audio.status()
        byt.debug_position(status.completed, #audio.completions())
    end,
    draw = function()
        byt.clear(byt.rgb(20, 28, 44))
        byt.text("DSP LOAD: 16 VOICES / 8 BUSES / 320 NODES", 8, 20, byt.rgb(240, 240, 240))
    end,
}

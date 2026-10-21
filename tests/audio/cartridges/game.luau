--!strict
local byt = require("@bytorio")
local audio, data = byt.audio, byt.data
return {
    init = function()
        local values = { 0, 8192, 16384, 24576, 32767, 24576, 16384, 8192 }
        local signed = buffer.create(16)
        for i, value in values do
            buffer.writei16(signed, (i - 1) * 2, value)
        end
        local pcm = data.from_i16(signed, 1)
        local sample = audio.sample({ frames = 8, channels = 1, rate = 24000 }, pcm)
        local bus = audio.bus({ gain = 0.5 })
        local v = audio.voice(0)
        audio.play_sample(
            v,
            sample,
            { bus = bus, loop = true, loop_start = 2, loop_end = 8, gain = 0.5, pan = -0.25 }
        )
        audio.play_sample(audio.voice(1), sample, { at = 24, gain = 0.25, pan = 0.5 })
        audio.gain(v, 1, 64, 32)
        audio.pan(v, 0.5, 128, 32)
        audio.bus_gain(bus, 0.25, 192, 16)
        audio.release(v, 20, 300)
        audio.play_sample(audio.voice(3), sample, { loop = true, loop_end = 8, gain = 0.02 })
        local stream = audio.stream()
        local stereo = data.pcm(128, 2)
        for i = 0, 127 do
            buffer.writef32(stereo.samples, i * 8, 0.2)
            buffer.writef32(stereo.samples, i * 8 + 4, -0.2)
        end
        audio.write_stream(stream, 512, stereo)
        audio.play_stream(audio.voice(2), stream, { at = 480, gain = 0.5 })
        audio.stop(audio.voice(2), 640)
        local short = data.pcm(64, 2)
        buffer.copy(short.samples, 0, stereo.samples, 0, 512)
        audio.write_stream(stream, 800, short)
        audio.play_stream(audio.voice(2), stream, { at = 768, gain = 0.5 })
        audio.stop(audio.voice(2), 880)
        buffer.fill(pcm.samples, 0, 0)
    end,
    update = function(_dt: number)
        local status = audio.status()
        byt.debug_position(status.completed, #audio.completions())
    end,
    draw = function()
        byt.clear(byt.rgb(20, 28, 44))
        byt.rect(24, 40, 272, 48, byt.rgb(64, 170, 205))
        byt.text("PCM MIXER: 4 VOICES + STREAM", 24, 20, byt.rgb(240, 240, 240))
    end,
}

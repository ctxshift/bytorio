--!strict
local byt = require("@bytorio")
local audio, data = byt.audio, byt.data

return {
    init = function()
        local pcm = data.pcm(4, 1)
        buffer.writef32(pcm.samples, 4, 0.125)
        buffer.writef32(pcm.samples, 12, -0.125)
        local sample = audio.sample({ frames = 4, channels = 1, rate = 8000 }, pcm)
        audio.play_sample(audio.voice(0), sample, { loop = true, loop_end = 4 })
    end,
    update = function(_dt: number)
        audio.gain(audio.voice(0), 0.1)
    end,
    draw = function()
        byt.clear(byt.rgb(20, 28, 44))
    end,
}

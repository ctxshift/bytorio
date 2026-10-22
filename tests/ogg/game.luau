--!strict
local byt = require("@bytorio")
local audio = byt.audio

return {
    init = function()
        local music = audio.ogg_stream(1, { loop = true, loop_start = 431, loop_end = 4199 })
        local effect = audio.ogg_stream(1)
        local shortLoop = audio.ogg_stream(1, { loop = true, loop_start = 431, loop_end = 432 })
        audio.play_stream(audio.voice(0), music, { gain = 0.5 })
        audio.play_stream(audio.voice(1), effect, { gain = 0.25 })
        audio.play_stream(audio.voice(2), shortLoop, { gain = 0.125 })
    end,
    update = function(_dt: number) end,
    draw = function()
        byt.clear(byt.rgb(20, 28, 44))
    end,
}

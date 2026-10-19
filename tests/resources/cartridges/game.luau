--!strict
local console = require("@console")
local gfx, audio, data = console.gfx, console.audio, console.data
local image: console.Texture
local sound: console.Sample
local pixels = data.pixels("rgba8", 2, 2)
local pcm = data.pcm(4, 2)
return {
    init = function()
        buffer.fill(pixels.bytes, 0, 255)
        buffer.writef32(pcm.samples, 0, 0.25)
        buffer.writef32(pcm.samples, 4, -0.25)
        image = gfx.texture({format = "rgba8", width = 2, height = 2})
        gfx.upload(image, {x = 0, y = 0, width = 2, height = 2}, pixels)
        sound = audio.sample({frames = 4, channels = 2, rate = 48000}, pcm)
        buffer.fill(pixels.bytes, 0, 0)
        buffer.fill(pcm.samples, 0, 0)
    end,
    update = function(_dt: number)
        if console.button("up") then
            gfx.destroy(image)
            gfx.upload(image, {x = 0, y = 0, width = 2, height = 2}, pixels)
        end
        local tick = console.ticks()
        if tick == 2 then
            buffer.fill(pixels.bytes, 0, 128)
            gfx.upload(image, {x = 0, y = 0, width = 2, height = 2}, pixels)
            buffer.fill(pixels.bytes, 0, 0)
        elseif tick == 3 then
            audio.write(sound, {first = 0, frames = 4}, pcm)
        elseif tick == 4 then
            gfx.destroy(image); audio.destroy(sound)
        elseif tick == 5 then
            image = gfx.texture({format = "index8", width = 3, height = 1})
        end
    end,
    draw = function() console.clear(console.rgb(16, 24, 32)) end,
}

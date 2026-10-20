--!strict
local console = require("@console")
local gfx, audio, data = console.gfx, console.audio, console.data

local IMAGE_WIDTH = 2
local IMAGE_HEIGHT = 2
local SAMPLE_FRAMES = 4
local SAMPLE_CHANNELS = 2
local SAMPLE_RATE = 48000

local image: console.Texture
local sound: console.Sample
local pixels = data.pixels("rgba8", IMAGE_WIDTH, IMAGE_HEIGHT)
local pcm = data.pcm(SAMPLE_FRAMES, SAMPLE_CHANNELS)

local function uploadImage()
    gfx.upload(image, { x = 0, y = 0, width = IMAGE_WIDTH, height = IMAGE_HEIGHT }, pixels)
end

local function init()
    buffer.fill(pixels.bytes, 0, 255)
    buffer.writef32(pcm.samples, 0, 0.25)
    buffer.writef32(pcm.samples, 4, -0.25)

    image = gfx.texture({ format = "rgba8", width = IMAGE_WIDTH, height = IMAGE_HEIGHT })
    uploadImage()
    sound = audio.sample(
        { frames = SAMPLE_FRAMES, channels = SAMPLE_CHANNELS, rate = SAMPLE_RATE },
        pcm
    )

    -- Uploads snapshot their input. Reusing staging memory cannot change them.
    buffer.fill(pixels.bytes, 0, 0)
    buffer.fill(pcm.samples, 0, 0)
end

local function provokeStaleHandleError()
    -- Deliberate negative fixture: the host must reject this whole transaction.
    gfx.destroy(image)
    uploadImage()
end

local function update(_dt: number)
    if console.button("up") then
        provokeStaleHandleError()
    end

    -- Fixed ticks make this example a reproducible lifecycle conformance trace.
    local tick = console.ticks()
    if tick == 2 then
        buffer.fill(pixels.bytes, 0, 128)
        uploadImage()
        buffer.fill(pixels.bytes, 0, 0)
    elseif tick == 3 then
        audio.write(sound, { first = 0, frames = SAMPLE_FRAMES }, pcm)
    elseif tick == 4 then
        gfx.destroy(image)
        audio.destroy(sound)
    elseif tick == 5 then
        image = gfx.texture({ format = "index8", width = 3, height = 1 })
    end
end

local function draw()
    console.clear(console.rgb(16, 24, 32))
end

return {
    init = init,
    update = update,
    draw = draw,
}

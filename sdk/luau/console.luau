--!strict
local c = require("./constants")
local host = require("./native")
local resources = require("./resources")
local schema = require("./resource_schema")
export type Texture = resources.Texture
export type Target = resources.Target
export type Palette = resources.Palette
export type ColorTable = resources.ColorTable
export type RowTable = resources.RowTable
export type Pipeline = resources.Pipeline
export type Readback = resources.Readback
export type Pass = resources.Pass
export type Sample = resources.Sample
export type Wavetable = resources.Wavetable
export type Instrument = resources.Instrument
export type SynthNode = resources.SynthNode
export type AudioParameter = resources.Parameter
export type Bus = resources.Bus
export type Stream = resources.Stream
export type Voice = resources.Voice
export type AudioStatus = resources.AudioStatus
export type AudioCompletion = resources.Completion
export type PixelBuffer = resources.PixelBuffer
export type PCMBuffer = resources.PCMBuffer
export type Button = "left" | "right" | "up" | "down" | "action"
export type Game = { init: () -> (), update: (number) -> (), draw: () -> () }
local profileQuery = host.profile
local profile = if profileQuery then profileQuery() else 1
local api = { version = if profile == c.PROFILE_RESOURCE then "0.2.0" else "0.1.0" }
function api.capabilities()
    return table.freeze({
        profile = profile,
        abi = if profile == c.PROFILE_RESOURCE then c.RESOURCE_ABI_VERSION else 1,
        sdk = if profile == c.PROFILE_RESOURCE then c.RESOURCE_SDK_VERSION else 256,
        features = if profile == c.PROFILE_RESOURCE then c.RESOURCE_FEATURES else 0,
        protocol = if profile == c.PROFILE_RESOURCE then c.RESOURCE_PROTOCOL else 0,
        resource_bytes = schema.maxResourceBytes,
        slots = schema.maxSlots,
        payload_bytes = schema.maxPayload,
        audio_rate = schema.audioRate,
        audio_lead_frames = schema.audioLeadFrames,
    })
end
api.gfx = resources.gfx
api.audio = resources.audio
api.data = resources.data
local masks = { left = 1, right = 2, up = 4, down = 8, action = 16 }
local held, down, up, clock, randomState = 0, 0, 0, 0, c.DEFAULT_RANDOM_SEED
local width, height = 640, 360
local pointerActive, pointerX, pointerY = false, 0, 0
local phase = "load"
local function integer(value: number, lo: number, hi: number): number
    assert(
        value == math.floor(value) and value >= lo and value <= hi,
        "integer outside supported range"
    )
    return value
end
local function keyMask(key: Button): number
    return masks[key]
end
function api.display(w: number, h: number)
    assert((w == 640 and h == 360) or (w == 320 and h == 180), "unsupported display mode")
    width, height = w, h
    host.display(w, h)
end
function api.size(): (number, number)
    return width, height
end
function api.rgb(r: number, g: number, b: number): number
    return c.COLOR_OPAQUE_BLACK
        + integer(b, 0, c.COLOR_CHANNEL_MAX) * c.COLOR_BLUE_SCALE
        + integer(g, 0, c.COLOR_CHANNEL_MAX) * c.COLOR_GREEN_SCALE
        + integer(r, 0, c.COLOR_CHANNEL_MAX)
end
function api.clear(color: number)
    integer(color, c.COLOR_OPAQUE_BLACK, c.U32_MAX)
    if resources._in_pass() then
        resources.gfx.clear(resources.gfx.current_pass(), color)
    else
        host.clear(
            bit32.band(color, 255),
            bit32.band(bit32.rshift(color, 8), 255),
            bit32.band(bit32.rshift(color, 16), 255)
        )
    end
end
function api.rect(x: number, y: number, w: number, h: number, color: number)
    integer(color, c.COLOR_OPAQUE_BLACK, c.U32_MAX)
    if resources._in_pass() then
        resources.gfx.rect(resources.gfx.current_pass(), x, y, w, h, color)
    else
        host.rect(x, y, w, h, color)
    end
end
function api.sprite(id: number, x: number, y: number, scale: number?)
    integer(id, 0, 255)
    local s = integer(scale or 1, 1, 8)
    if resources._in_pass() then
        resources.gfx.sprite(resources.gfx.current_pass(), id, x, y, 16 * s, 16 * s)
    else
        host.draw_sprite(id, x, y, s)
    end
end
function api.sprite_size(id: number, x: number, y: number, w: number, h: number)
    integer(id, 0, 255)
    integer(w, 1, 128)
    integer(h, 1, 128)
    if resources._in_pass() then
        resources.gfx.sprite(resources.gfx.current_pass(), id, x, y, w, h)
    else
        host.draw_sprite_size(id, x, y, w, h)
    end
end
function api.text(value: string, x: number, y: number, color: number)
    assert(#value <= c.MAX_TEXT_BYTES_PER_COMMAND, "text command exceeds 1024 bytes")
    for i = 1, #value do
        assert(string.byte(value, i) < 128, "text must be ASCII")
    end
    integer(color, c.COLOR_OPAQUE_BLACK, c.U32_MAX)
    if resources._in_pass() then
        resources.gfx.text(resources.gfx.current_pass(), value, x, y, color)
    else
        host.draw_text(value, x, y, color)
    end
end
function api.assets(encoded: string)
    assert(phase == "load" or phase == "init", "graphics assets are immutable after init")
    host.graphics_assets(encoded)
end
function api.buttons(): number
    return held
end
function api.button(key: Button): boolean
    return bit32.band(held, keyMask(key)) ~= 0
end
function api.pressed(key: Button): boolean
    return bit32.band(down, keyMask(key)) ~= 0
end
function api.released(key: Button): boolean
    return bit32.band(up, keyMask(key)) ~= 0
end
function api.pointer(): (boolean, number, number)
    return pointerActive, pointerX, pointerY
end
function api.ticks(): number
    return clock
end
function api.sound()
    host.sound()
end
function api.seed(value: number)
    integer(value, 0, c.U32_MAX)
    randomState = if value == 0 then c.RANDOM_ZERO_SEED_FALLBACK else value
end
function api.random_u32(): number
    randomState = bit32.bxor(randomState, bit32.lshift(randomState, 13))
    randomState = bit32.bxor(randomState, bit32.rshift(randomState, 17))
    randomState = bit32.bxor(randomState, bit32.lshift(randomState, 5))
    return randomState
end
function api.debug_position(x: number, y: number)
    host.debug_position(x, y)
end
function api._wrap(game: Game, initialWidth: number?, initialHeight: number?): Game
    assert(
        type(game.init) == "function"
            and type(game.update) == "function"
            and type(game.draw) == "function",
        "missing game callback"
    )
    return {
        init = function()
            held, down, up, clock, randomState = 0, 0, 0, 0, c.DEFAULT_RANDOM_SEED
            pointerActive, pointerX, pointerY = false, 0, 0
            width, height = initialWidth or 640, initialHeight or 360
            host.display(width, height)
            resources._begin(0)
            phase = "init"
            game.init()
            phase = "ready"
            resources._end()
        end,
        update = function(dt: number)
            local nextHeld = bit32.band(host.buttons(), 31)
            down, up =
                bit32.band(nextHeld, bit32.bnot(held)), bit32.band(held, bit32.bnot(nextHeld))
            held = nextHeld
            clock = (clock + 1) % c.U32_MODULUS
            local active, x, y = host.pointer()
            pointerActive = active and x >= 0 and y >= 0 and x < width and y < height
            pointerX, pointerY = if pointerActive then x else 0, if pointerActive then y else 0
            resources._begin(clock)
            phase = "update"
            game.update(dt)
            phase = "ready"
            resources._end()
        end,
        draw = function()
            resources._begin_draw()
            phase = "draw"
            game.draw()
            phase = "ready"
            resources._end()
        end,
    }
end
return api

--!strict
local byt = require("@bytorio")
local text = byt.text_input
local lastFlags = 0

local function open(id: number, value: string)
    assert(text.configure({
        id = id,
        value = value,
        max_bytes = 12,
        x = 30,
        y = 30,
        width = 200,
        height = 32,
    }))
    lastFlags = 0
end

local function init()
    open(1, "Aé")
end

local function update(_dt: number)
    if byt.pressed("action") then
        text.close()
    end
    if byt.pressed("left") then
        open(2, "")
    end
    local event = text.read()
    if event then
        if event.id == 1 and not event.changed and lastFlags == 0 then
            assert(event.value == "Aé")
        end
        byt.sound()
        if event.changed then
            lastFlags = bit32.bor(lastFlags, 2)
            byt.sound()
        end
        if event.submitted then
            lastFlags = bit32.bor(lastFlags, 4)
        end
        if event.cancelled then
            lastFlags = bit32.bor(lastFlags, 8)
        end
        byt.debug_position(#event.value, lastFlags)
        assert(text.read() == nil)
    else
        byt.debug_position(-1, lastFlags)
    end
end

local function draw()
    byt.clear(byt.rgb(16, 32, 48))
end

return { init = init, update = update, draw = draw }

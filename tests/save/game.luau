--!strict
local byt = require("@bytorio")
local save = byt.save
local staging = buffer.create(save.max_bytes)

local function verifySaved()
    local length = save.read(staging)
    assert(length == save.size())
    assert(length == save.max_bytes or length == 3)
    for i = 0, length - 1 do
        local expected = if length == save.max_bytes then (i * 37 + 11) % 256 else i + 7
        assert(buffer.readu8(staging, i) == expected)
    end
    byt.sound()
end

local function init()
    if save.size() > 0 then
        verifySaved()
    end
end

local function update(_dt: number)
    if byt.pressed("action") then
        for i = 0, buffer.len(staging) - 1 do
            buffer.writeu8(staging, i, (i * 37 + 11) % 256)
        end
        local result = save.write(staging)
        assert(result == save.ready or result == save.pending)
        assert(save.write(staging) == save.error)
        buffer.fill(staging, 0, 0)
    end
    if byt.pressed("right") then
        verifySaved()
    end
    if byt.pressed("left") then
        assert(save.write(buffer.create(save.max_bytes + 1)) == save.error)
        assert(save.write(buffer.create(0)) == save.error)
        local small = buffer.create(1)
        buffer.writeu8(small, 0, 123)
        assert(save.read(small) == 0 and buffer.readu8(small, 0) == 123)
        byt.sound()
    end
    if byt.pressed("up") then
        local replacement = buffer.fromstring(string.char(7, 8, 9))
        local result = save.write(replacement)
        assert(result == save.ready or result == save.pending)
        buffer.fill(replacement, 0, 0)
    end
    byt.debug_position(save.size(), save.status())
end

local function draw()
    byt.clear(byt.rgb(16, 32, 48))
end
return { init = init, update = update, draw = draw }

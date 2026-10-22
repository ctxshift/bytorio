--!strict
local byt = require("@bytorio")

local function init()
    local content = byt.content
    assert(content.size(0) == 0)
    assert(content.size(9) == 0)
    assert(content.size(7) == 3 * 1024 * 1024)
    assert(content.size(0xffffffff) == 4)
    if content.size(8) ~= 0 then
        assert(content.size(8) == 65 * 1024 * 1024)
        local high = buffer.create(4)
        assert(content.read(8, 64 * 1024 * 1024 + 1023, high))
        assert(buffer.readu32(high, 0) == 0x020100ff)
        assert(content.read(8, content.size(8) - 4, high))
        assert(buffer.readu32(high, 0) == 0xfffefdfc)
    end
    local bytes = buffer.create(4)
    assert(content.read(7, 1023, bytes))
    assert(buffer.readu32(bytes, 0) == 0x020100ff)
    assert(not content.read(7, content.size(7) - 3, bytes))
    assert(buffer.readu32(bytes, 0) == 0x020100ff)
    assert(not content.read(7, 0xffffffff, bytes))
    assert(not content.read(9, 0, bytes))
    assert(content.read(7, content.size(7), buffer.create(0)))
    assert(not content.read(7, 0, buffer.create(1048577)))
    assert(content.read(0xffffffff, 0, bytes))
    assert(buffer.readu32(bytes, 0) == 0x59291711)
    byt.debug_position(17, 89)
end

local function update(_dt: number)
    local bytes = buffer.create(4)
    assert(byt.content.read(0xffffffff, 0, bytes))
    assert(buffer.readu8(bytes, 2) == 41)
end

local function draw()
    byt.clear(byt.rgb(17, 23, 41))
end

local game: byt.Game = { init = init, update = update, draw = draw }
return game

--!strict
local byt = require("@bytorio")
local x, y = 40, 40
local function init()
    x, y = 40, 40
    byt.sound()
end
local function update(dt: number)
    if byt.button("left") then
        x -= 90 * dt
    end
    if byt.button("right") then
        x += 90 * dt
    end
    if byt.button("up") then
        y -= 90 * dt
    end
    if byt.button("down") then
        y += 90 * dt
    end
    local active, px, py = byt.pointer()
    if active then
        x, y = px - 8, py - 8
    end
    local w, h = byt.size()
    x, y = math.clamp(x, 0, w - 16), math.clamp(y, 20, h - 16)
    if byt.pressed("action") then
        byt.sound()
    end
end
local function draw()
    byt.clear(byt.rgb(23, 32, 46))
    byt.sprite(0, x, y)
    byt.text("__STARTER_MESSAGE__", 8, 7, byt.rgb(244, 236, 214))
end
local game: byt.Game = { init = init, update = update, draw = draw }
return game

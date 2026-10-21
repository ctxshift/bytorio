--!strict
local byt = require("@bytorio")
local random, edges = 0, 0
local px, py = 0, 0
local function init()
    random, edges = 0, 0
    byt.seed(123)
    byt.sound()
end
local function update(dt: number)
    assert(dt == 1 / 60)
    if byt.pressed("action") then
        edges += 1
        byt.sound()
    end
    if byt.released("action") then
        edges += 10
    end
    local active, x, y = byt.pointer()
    px, py = if active then x else 0, if active then y else 0
    random = byt.random_u32() % 1000
    if byt.ticks() == 20 or byt.ticks() == 60 then
        byt.display(320, 180)
    end
    if byt.ticks() == 40 then
        byt.display(640, 360)
    end
    byt.debug_position(random, edges)
end
local function draw()
    byt.clear(byt.rgb(23, 32, 46))
    byt.rect(-2, -2, 8, 8, byt.rgb(255, 0, 0))
    byt.rect(12, 12, 0, 20, byt.rgb(0, 0, 0))
    byt.sprite(0, -4, 8, 2)
    byt.sprite_size(0, 60, 30, 7 + byt.ticks() % 25, 11)
    byt.text("SDK\nPARITY", 20, 50, byt.rgb(255, 255, 255))
    byt.rect(math.floor(px), math.floor(py), 3, 3, byt.rgb(0, 255, 0))
    if byt.button("right") then
        byt.rect(40, 90, 8, 8, byt.rgb(0, 0, 255))
    end
end
return { init = init, update = update, draw = draw }

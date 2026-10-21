--!strict
local byt = require("@bytorio")
local random, edges = 0, 0
local px, py = 0, 0
local inputProbe = false
local function init()
    random, edges = 0, 0
    inputProbe = false
    byt.seed(123)
    byt.sound()
end
local function update(dt: number)
    assert(dt == 1 / 60)
    local tick = byt.ticks()
    if tick > 120 and byt.wheel() ~= 0 then
        byt.sound()
    end
    if tick == 81 and byt.all_buttons() ~= 0 then
        inputProbe = true
        byt.sound()
    end
    if inputProbe and tick >= 81 and tick <= 88 then
        assert(byt.capabilities().input_version == 2)
        assert(byt.buttons() == 0)
        local hover, hx, hy = byt.pointer_position()
        local active, legacyX, legacyY = byt.pointer()
        if tick == 81 or tick == 82 then
            assert(byt.all_buttons() == 0xffff0000)
            assert(hover and hx == 80.5 and hy == 60.75)
            assert(not active and legacyX == 0 and legacyY == 0)
            local keys: { byt.Button } = {
                "pointer_left",
                "pointer_right",
                "pointer_hover",
                "wheel_up",
                "wheel_down",
                "inventory",
                "character",
                "skills",
                "quest",
                "map",
                "potion_1",
                "potion_2",
                "potion_3",
                "potion_4",
                "shift",
                "escape",
            }
            for _, key in keys do
                assert(byt.button(key))
                assert(byt.pressed(key) == (tick == 81))
                assert(not byt.released(key))
            end
            assert(byt.wheel() == 0)
        elseif tick == 83 then
            assert(byt.released("escape") and byt.released("pointer_right"))
            assert(not hover and hx == 0 and hy == 0)
        elseif tick == 84 then
            assert(not hover and hx == 0 and hy == 0)
        elseif tick == 85 then
            assert(byt.wheel() == 1)
        elseif tick == 86 then
            assert(byt.wheel() == -1)
        elseif tick == 87 then
            assert(active and legacyX == 17.25 and legacyY == 18.5)
            assert(hover and hx == 17.25 and hy == 18.5)
        else
            assert(not active and not hover and byt.wheel() == 0)
            assert(byt.released("pointer_left"))
        end
    end
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

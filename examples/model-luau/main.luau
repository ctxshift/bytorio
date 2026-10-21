--!strict
local console = require("@console")
local model = require("./imported/model")

local g, gfx = console.gfx3d, console.gfx
local instance: model.Instance
local transforms: { { number } }
local base: { { number } }
local depthLow: console.Depth
local depthHigh: console.Depth
local camera: console.Camera
local tick = 0

local function init()
    tick = 0
    console.display(320, 180)
    depthLow = g.depth(320, 180)
    depthHigh = g.depth(640, 360)
    local view = g.look_at({ 5, 3, -8 }, { 1, 0.5, -2 })
    camera = g.camera({
        view_projection = g.multiply(g.perspective(math.pi / 3, 16 / 9, 0.1, 40), view),
    })
    instance = model.create()
    base = model.local_transforms()
    transforms = model.local_transforms()
end

local function update(_dt: number)
    console.display(
        if console.button("action") then 640 else 320,
        if console.button("action") then 360 else 180
    )
    if console.button("down") then
        model.destroy(instance)
    elseif not instance.alive then
        instance = model.create()
    end
    if console.button("right") then
        tick += 1
    elseif console.button("left") then
        tick -= 1
    end
    local body, wheel = model.index("body"), model.index("wheel")
    transforms[body] = g.multiply(base[body], g.pose(0, 0, 0, tick * 0.125, 1))
    transforms[wheel] = g.multiply(base[wheel], g.pose(0, 0, 0, tick * 0.25, 1))
end

local function draw()
    local pass = gfx.begin_pass(gfx.screen(), { clear = true, color = 0xff322015 })
    g.bind(pass, if console.button("action") then depthHigh else depthLow, camera)
    if instance.alive then
        model.draw(pass, instance, nil, transforms)
    end
    gfx.text(pass, "IMPORTED RIGID MODEL", 6, 6, 0xffffffff)
    gfx.text(pass, "ARROWS: TURN / DOWN: RELEASE / ACTION: HD", 6, 166, 0xffffffff)
    gfx.end_pass(pass)
    gfx.present(gfx.screen())
end

return { init = init, update = update, draw = draw }

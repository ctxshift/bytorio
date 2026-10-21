--!strict
local byt = require("@bytorio")
local race = require("./race")
local scene = require("./scene")
local course = require("./course")
local hud = require("./hud")
local g, gfx = byt.gfx3d, byt.gfx
local SKY = 0xffe8b875
local s = race.new()
local assets: typeof(scene.create())
local depths: { byt.Depth }
local camera: byt.Camera
local eye = { 0, 0, 0 }
local high = false

local function cameraUpdate(first: boolean?)
    local p, yaw = scene.sample(s.distance, s.lateral)
    local desired =
        { p[1] - math.sin(yaw) * 5.8, p[2] + 3.0, p[3] - math.sin(yaw + math.pi / 2) * 5.8 }
    for i, value in desired do
        eye[i] = if first then value else math.floor((eye[i] + (value - eye[i]) / 5) * 256) / 256
    end
    local target = scene.sample(s.distance + 1300, s.lateral)
    target[2] += 0.9
    if not first then
        g.destroy(camera)
    end
    camera = g.camera({
        view_projection = g.multiply(
            g.perspective(55 * math.pi / 180, 16 / 9, 0.2, 95),
            g.look_at(eye, target)
        ),
        ambient = 1,
        fog_color = SKY,
        fog_start = 0.996,
        fog_end = 1,
    })
end
local function init()
    s = race.new()
    high = false
    byt.display(320, 180)
    depths = { g.depth(320, 180), g.depth(640, 360) }
    assets = scene.create()
    cameraUpdate(true)
end
local function update(_dt: number)
    local events = s.events
    race.step(s, byt.all_buttons())
    if byt.pressed("rotate_left") then
        high = not high
    end
    byt.display(if high then 640 else 320, if high then 360 else 180)
    if s.events > events then
        byt.sound()
    end
    cameraUpdate()
    byt.debug_position((s.distance % 98304) / 1024, s.lateral / 128)
end
local rotationScratch = buffer.create(8)
local function rotationX(angle: number): { number }
    buffer.writef32(rotationScratch, 0, math.sin(angle + math.pi / 2))
    buffer.writef32(rotationScratch, 4, math.sin(angle))
    local c, v = buffer.readf32(rotationScratch, 0), buffer.readf32(rotationScratch, 4)
    return { 1, 0, 0, 0, 0, c, v, 0, 0, -v, c, 0, 0, 0, 0, 1 }
end
local function drawKart(
    pass: byt.Pass,
    index: number,
    distance: number,
    lane: number,
    heading: number?,
    hop: number?
)
    local p, yaw = scene.sample(distance, lane)
    local player = scene.sample(s.distance, s.lateral)
    if index ~= 1 and (p[1] - player[1]) ^ 2 + (p[3] - player[3]) ^ 2 > 75 * 75 then
        return
    end
    local lift = math.sin((hop or 0) * math.pi / 12) * 0.55
    local pitch = rotationX(course[math.floor((distance % 98304) / 1024) + 1][8])
    g.draw(pass, assets.shadow, g.multiply(g.pose(p[1], p[2], p[3], yaw, 1), pitch))
    local model =
        g.multiply(g.pose(p[1], p[2] + 0.04 + lift, p[3], yaw + (heading or 0) / 512, 1), pitch)
    g.draw(pass, assets.bodies[index], model)
    local spin = (distance % 4096) / 256
    local rotation = rotationX(spin)
    for _, x in { -0.95, 0.95 } do
        for _, z in { -0.72, 0.72 } do
            g.draw(
                pass,
                assets.wheel,
                g.multiply(model, g.multiply(g.pose(x, 0.35, z, 0, 1), rotation))
            )
        end
    end
    if index == 1 and (s.charge > 0 or s.boost > 0) then
        for _, x in { -0.85, 0.85 } do
            g.draw(pass, assets.spark, g.multiply(model, g.pose(x, 0.3, -1.3, 0, 1 + s.charge)))
        end
    end
end
local function draw()
    local pass = gfx.begin_pass(gfx.screen(), { clear = true, color = SKY })
    g.bind(pass, depths[if high then 2 else 1], camera)
    g.draw(pass, assets.ground)
    local chunk = math.floor((math.floor(s.distance / 1024) % 96) / 8)
    for offset = -3, 3 do
        g.draw(pass, assets.chunks[(chunk + offset + 12) % 12 + 1])
    end
    for i = 2, 8 do
        drawKart(pass, i, s.rivals[i - 1], ((i - 2) % 3 - 1) * 370)
    end
    drawKart(pass, 1, s.distance, s.lateral, s.heading + s.drift * 45, s.hop)
    local nextPickup = (math.floor(s.distance / (1024 * 12)) + 1) * (1024 * 12)
    for _, lane in { -333, 0, 333 } do
        local p = scene.sample(nextPickup, lane)
        g.draw(pass, assets.pickup, g.pose(p[1], p[2] + 1, p[3], s.tick / 50, 1))
    end
    hud.draw(pass, s, high)
    gfx.end_pass(pass)
    gfx.present(gfx.screen())
end
return { init = init, update = update, draw = draw }

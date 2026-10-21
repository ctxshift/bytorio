--!strict
local byt = require("@bytorio")
local gfx, g = byt.gfx, byt.gfx3d

local ORBIT_VIEWS = 32
local ART_SIZE = 8
local views: { { number } } = {}
local cameras: { byt.Camera } = {}
local depthLow: byt.Depth
local depthHigh: byt.Depth
local quad: byt.TexturedMesh
local ground: byt.Mesh
local road: byt.Mesh
local kart: byt.Mesh
local tree: byt.Material
local fence: byt.Material
local shadow: byt.Material
local item: byt.Material
local viewIndex = 1
local smoke: byt.Material
local glow: byt.Material
local particleTick = 0

local function art(kind: number): byt.Material
    local pixels = byt.data.pixels("rgba8", ART_SIZE, ART_SIZE)
    for y = 0, ART_SIZE - 1 do
        for x = 0, ART_SIZE - 1 do
            local color = 0
            local dx, dy = x - 3, y - 3
            if kind == 0 then
                if y < 5 and dx * dx + (y - 2) * (y - 2) <= 9 then
                    color = 0xff4ea653
                end
                if y >= 4 and (x == 3 or x == 4) then
                    color = 0xff345e8c
                end
            elseif kind == 1 then
                if x == 0 or x == 7 or y == 2 or y == 5 then
                    color = 0xffd9ecec
                end
            elseif kind == 2 then
                if dx * dx + dy * dy <= 10 then
                    color = 0xff202020
                end
            elseif kind == 4 or kind == 5 then
                if dx * dx + dy * dy <= 10 then
                    color = if kind == 4 then 0x60403828 else 0x80206080
                end
            elseif kind == 3 then
                if math.abs(dx) + math.abs(dy) <= 3 then
                    color = 0xff45c5f4
                end
            end
            buffer.writeu32(pixels.bytes, (y * ART_SIZE + x) * 4, color)
        end
    end
    local texture = gfx.texture({ format = "rgba8", width = ART_SIZE, height = ART_SIZE })
    gfx.upload(texture, { x = 0, y = 0, width = ART_SIZE, height = ART_SIZE }, pixels)
    if kind >= 4 then
        return g.effect_material(texture, { blend = if kind == 5 then "additive" else "alpha" })
    end
    return g.cutout_material(texture)
end

local function plane(
    left: number,
    right: number,
    near: number,
    far: number,
    height: number,
    color: number
): byt.Mesh
    return g.mesh({
        { position = { left, height, near }, color = color },
        { position = { right, height, near }, color = color },
        { position = { right, height, far }, color = color },
        { position = { left, height, far }, color = color },
    }, { 0, 2, 1, 0, 3, 2 })
end

local function init()
    assert(byt.capabilities().profile == 6)
    smoke, glow = art(4), art(5)
    particleTick = 0
    byt.display(320, 180)
    viewIndex = 1
    views, cameras = {}, {}
    depthLow, depthHigh = g.depth(320, 180), g.depth(640, 360)
    local projection = g.perspective(math.pi / 3, 16 / 9, 0.1, 40)
    for index = 0, ORBIT_VIEWS - 1 do
        local angle = index * 2 * math.pi / ORBIT_VIEWS
        views[index + 1] = g.look_at(
            { math.sin(angle) * 8, 5, -math.sin(angle + math.pi / 2) * 8 },
            { 0, 0.6, 2 }
        )
        cameras[index + 1] =
            g.camera({ view_projection = g.multiply(projection, views[index + 1]) })
    end
    quad = g.billboard()
    tree, fence, shadow, item = art(0), art(1), art(2), art(3)
    ground = plane(-6, 6, -3, 9, 0, 0xff497b40)
    road = plane(-1.8, 1.8, -3, 9, 0.01, 0xff636572)
    local vertices = {}
    for index, point in
        {
            { -0.7, 0.15, 1 },
            { 0.7, 0.15, 1 },
            { 0.7, 0.15, 2.3 },
            { -0.7, 0.15, 2.3 },
            { -0.7, 0.85, 1 },
            { 0.7, 0.85, 1 },
            { 0.7, 0.85, 2.3 },
            { -0.7, 0.85, 2.3 },
        }
    do
        table.insert(
            vertices,
            { position = point, color = if index <= 4 then 0xff3339a0 else 0xff5759ef }
        )
    end
    kart = g.mesh(vertices, {
        0,
        2,
        1,
        0,
        3,
        2,
        4,
        5,
        6,
        4,
        6,
        7,
        0,
        1,
        5,
        0,
        5,
        4,
        1,
        2,
        6,
        1,
        6,
        5,
        2,
        3,
        7,
        2,
        7,
        6,
        3,
        0,
        4,
        3,
        4,
        7,
    })
end

local function update(_dt: number)
    particleTick += 1
    local high = byt.button("action")
    byt.display(if high then 640 else 320, if high then 360 else 180)
    if byt.button("right") then
        viewIndex = viewIndex % ORBIT_VIEWS + 1
    end
    if byt.button("left") then
        viewIndex = (viewIndex + ORBIT_VIEWS - 2) % ORBIT_VIEWS + 1
    end
end

local function draw()
    local pass = gfx.begin_pass(gfx.screen(), { clear = true, color = 0xffb99a79 })
    g.bind(pass, if byt.button("action") then depthHigh else depthLow, cameras[viewIndex])
    g.draw(pass, ground)
    g.draw(pass, road)
    local shadowModel = g.identity()
    shadowModel[1], shadowModel[6], shadowModel[7] = 2, 0, 1.8
    shadowModel[10], shadowModel[11] = -1, 0
    shadowModel[13], shadowModel[14], shadowModel[15] = -1, 0.03, 0.7
    g.draw_textured(pass, quad, shadow, shadowModel)
    for _, position in { { -2.2, 0, 0 }, { 2, 0, 3.5 }, { -1, 0, 5 } } do
        g.draw_billboard(pass, quad, tree, {
            position = position,
            size = { 2, 3.4 },
            pivot = { 0.5, 0 },
            view = views[viewIndex],
            mode = "upright",
        })
    end
    g.draw_billboard(pass, quad, fence, {
        position = { 0, 0, 3.1 },
        size = { 4, 1.3 },
        pivot = { 0.5, 0 },
        view = views[viewIndex],
        mode = "upright",
    })
    g.draw_billboard(pass, quad, item, {
        position = { 0, 2, 1.7 },
        size = { 0.8, 0.8 },
        pivot = { 0.5, 0.5 },
        view = views[viewIndex],
        rotation = 0.2,
    })
    g.draw(pass, kart)
    -- Fixed storage and deterministic ages keep the particle workload bounded.
    local order, positions, depths = {}, {}, {}
    for i = 1, 16 do
        local slot = i - 1
        local age = ((particleTick + slot * 3) % 48) / 48
        local p = { -0.65 + (slot % 2) * 1.3, 0.3 + age, 1.1 - age * 2.4 }
        positions[i] = p
        local view = views[viewIndex]
        depths[i] = view[3] * p[1] + view[7] * p[2] + view[11] * p[3]
        order[i] = i
        local j = i
        while j > 1 and depths[order[j]] > depths[order[j - 1]] do
            order[j], order[j - 1] = order[j - 1], order[j]
            j -= 1
        end
    end
    for _, i in order do
        g.draw_billboard(pass, quad, if (i - 1) % 3 == 0 then glow else smoke, {
            position = positions[i],
            size = { 0.55, 0.55 },
            pivot = { 0.5, 0.5 },
            view = views[viewIndex],
        })
    end
    gfx.text(pass, "CUTOUT / SMOKE / ADDITIVE", 6, 6, 0xffffffff)
    gfx.text(pass, "LEFT/RIGHT: ORBIT  ACTION: 640X360", 6, 166, 0xffffffff)
    gfx.end_pass(pass)
    gfx.present(gfx.screen())
end

local game: byt.Game = { init = init, update = update, draw = draw }
return game

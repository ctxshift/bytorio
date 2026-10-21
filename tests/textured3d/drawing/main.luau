--!strict
local byt = require("@bytorio")

local depth: byt.Depth
local depthHigh: byt.Depth
local camera: byt.Camera
local mesh: byt.TexturedMesh
local material: byt.Material
local texture: byt.Texture

local function init()
    byt.display(320, 180)
    depth = byt.gfx3d.depth(320, 180)
    depthHigh = byt.gfx3d.depth(640, 360)
    local projection = byt.gfx3d.identity()
    projection[11], projection[12], projection[16] = 0.5, 1, 0
    camera = byt.gfx3d.camera({
        view_projection = projection,
        ambient = 1,
        fog_color = 0xff000000,
        fog_start = 1,
        fog_end = 2,
    })
    local pixels = byt.data.pixels("rgba8", 1, 4)
    for row = 0, 3 do
        buffer.writeu8(pixels.bytes, row * 4 + row % 3, 255)
        buffer.writeu8(pixels.bytes, row * 4 + 3, 255)
    end
    texture = byt.gfx.texture({ format = "rgba8", width = 1, height = 4 })
    byt.gfx.upload(texture, { x = 0, y = 0, width = 1, height = 4 }, pixels)
    material = byt.gfx3d.material(texture, { address_v = "repeat" })
    mesh = byt.gfx3d.textured_mesh({
        { position = { -1, -1, 1 }, color = 0xffffffff, uv = { 0, 0 } },
        { position = { 2, -2, 2 }, color = 0xffffffff, uv = { 0, 0 } },
        { position = { 0, 4, 4 }, color = 0xffffffff, uv = { 0, 1.2 } },
    }, { 0, 1, 2 })
end

local function update(_dt: number)
    local high = byt.button("action")
    byt.display(if high then 640 else 320, if high then 360 else 180)
    if byt.button("up") and byt.ticks() == 3 then
        local pixels = byt.data.pixels("rgba8", 1, 1)
        buffer.writeu8(pixels.bytes, 0, 128)
        buffer.writeu8(pixels.bytes, 3, 255)
        byt.gfx.upload(texture, { x = 0, y = 1, width = 1, height = 1 }, pixels)
    end
end

local function draw()
    local pass = byt.gfx.begin_pass(byt.gfx.screen(), { clear = true, color = 0xff222222 })
    byt.gfx3d.bind(pass, if byt.button("action") then depthHigh else depth, camera)
    local shift = if byt.button("right") then byt.ticks() * 0.001 else 0
    byt.gfx3d.draw_textured(pass, mesh, material, byt.gfx3d.pose(shift, 0, 0, 0, 1))
    byt.gfx.end_pass(pass)
    byt.gfx.present(byt.gfx.screen())
end

local game: byt.Game = { init = init, update = update, draw = draw }
return game

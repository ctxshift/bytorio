--!strict
local console = require("@console")

local depth: console.Depth
local depthHigh: console.Depth
local camera: console.Camera
local mesh: console.TexturedMesh
local material: console.Material
local texture: console.Texture

local function init()
    console.display(320, 180)
    depth = console.gfx3d.depth(320, 180)
    depthHigh = console.gfx3d.depth(640, 360)
    local projection = console.gfx3d.identity()
    projection[11], projection[12], projection[16] = 0.5, 1, 0
    camera = console.gfx3d.camera({
        view_projection = projection,
        ambient = 1,
        fog_color = 0xff000000,
        fog_start = 1,
        fog_end = 2,
    })
    local pixels = console.data.pixels("rgba8", 1, 4)
    for row = 0, 3 do
        buffer.writeu8(pixels.bytes, row * 4 + row % 3, 255)
        buffer.writeu8(pixels.bytes, row * 4 + 3, 255)
    end
    texture = console.gfx.texture({ format = "rgba8", width = 1, height = 4 })
    console.gfx.upload(texture, { x = 0, y = 0, width = 1, height = 4 }, pixels)
    material = console.gfx3d.material(texture, { address_v = "repeat" })
    mesh = console.gfx3d.textured_mesh({
        { position = { -1, -1, 1 }, color = 0xffffffff, uv = { 0, 0 } },
        { position = { 2, -2, 2 }, color = 0xffffffff, uv = { 0, 0 } },
        { position = { 0, 4, 4 }, color = 0xffffffff, uv = { 0, 1.2 } },
    }, { 0, 1, 2 })
end

local function update(_dt: number)
    local high = console.button("action")
    console.display(if high then 640 else 320, if high then 360 else 180)
    if console.button("up") and console.ticks() == 3 then
        local pixels = console.data.pixels("rgba8", 1, 1)
        buffer.writeu8(pixels.bytes, 0, 128)
        buffer.writeu8(pixels.bytes, 3, 255)
        console.gfx.upload(texture, { x = 0, y = 1, width = 1, height = 1 }, pixels)
    end
end

local function draw()
    local pass = console.gfx.begin_pass(console.gfx.screen(), { clear = true, color = 0xff222222 })
    console.gfx3d.bind(pass, if console.button("action") then depthHigh else depth, camera)
    local shift = if console.button("right") then console.ticks() * 0.001 else 0
    console.gfx3d.draw_textured(pass, mesh, material, console.gfx3d.pose(shift, 0, 0, 0, 1))
    console.gfx.end_pass(pass)
    console.gfx.present(console.gfx.screen())
end

local game: console.Game = { init = init, update = update, draw = draw }
return game

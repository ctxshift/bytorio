--!strict
local byt = require("@bytorio")

local texture: byt.Texture
local mesh: byt.TexturedMesh
local material: byt.Material

local function createResources()
    local pixels = byt.data.pixels("rgba8", 2, 2)
    buffer.fill(pixels.bytes, 0, 255)
    texture = byt.gfx.texture({ format = "rgba8", width = 2, height = 2 })
    byt.gfx.upload(texture, { x = 0, y = 0, width = 2, height = 2 }, pixels)
    local vertices = {
        { position = { -1, -1, 0.5 }, color = 0xffffffff, uv = { -0.25, 0 } },
        { position = { 1, -1, 0.5 }, color = 0xff0000ff, uv = { 1.25, 0 } },
        { position = { 0, 1, 0.5 }, color = 0xff00ff00, uv = { 0.5, 1 } },
    }
    mesh = byt.gfx3d.textured_mesh(vertices, { 0, 1, 2 })
    material = byt.gfx3d.material(texture, { address_u = "repeat", address_v = "clamp" })
    buffer.fill(pixels.bytes, 0, 0)
    for _, vertex in vertices do
        vertex.uv = { 99, 99 }
    end
end

local function init()
    local capabilities = byt.capabilities()
    assert(capabilities.profile == 4 and capabilities.sdk == 1024 and capabilities.protocol == 6)
    createResources()
end

local function update(_dt: number)
    if byt.ticks() == 2 then
        local pixels = byt.data.pixels("rgba8", 2, 2)
        buffer.fill(pixels.bytes, 0, 128)
        byt.gfx.upload(texture, { x = 0, y = 0, width = 2, height = 2 }, pixels)
    elseif byt.ticks() == 3 then
        byt.gfx3d.destroy(material)
        byt.gfx3d.destroy(mesh)
        byt.gfx.destroy(texture)
    elseif byt.ticks() == 4 then
        createResources()
    end
end

local function draw()
    byt.clear(0xff201810)
end

local game: byt.Game = { init = init, update = update, draw = draw }
return game

--!strict
-- Generated model. Reimport the asset to change geometry; animate local transforms in game code.
local console = require("@console")
local g, gfx, data = console.gfx3d, console.gfx, console.data
type Matrix = { number }
type Address = "clamp" | "repeat"
type MaterialOptions = { address_u: Address?, address_v: Address? }
export type Instance = {
    alive: boolean,
    meshes: { console.TexturedMesh },
    materials: { console.Material },
    textures: { console.Texture },
}
local geometry = {
    {
        vertices = {
            { position = { -1, 0, 0.5 }, uv = { 0, 1 }, color = 4294934783 },
            { position = { 1, 0, 0.5 }, uv = { 1, 1 }, color = 4294934783 },
            { position = { 1, 1, 0.5 }, uv = { 1, 0 }, color = 4294934783 },
            { position = { -1, 1, 0.5 }, uv = { 0, 0 }, color = 4294934783 },
            { position = { 1, 0, -0.5 }, uv = { 0, 1 }, color = 4294934783 },
            { position = { -1, 0, -0.5 }, uv = { 1, 1 }, color = 4294934783 },
            { position = { -1, 1, -0.5 }, uv = { 1, 0 }, color = 4294934783 },
            { position = { 1, 1, -0.5 }, uv = { 0, 0 }, color = 4294934783 },
            { position = { -1, 0, -0.5 }, uv = { 0, 1 }, color = 4294934783 },
            { position = { -1, 0, 0.5 }, uv = { 1, 1 }, color = 4294934783 },
            { position = { -1, 1, 0.5 }, uv = { 1, 0 }, color = 4294934783 },
            { position = { -1, 1, -0.5 }, uv = { 0, 0 }, color = 4294934783 },
            { position = { 1, 0, 0.5 }, uv = { 0, 1 }, color = 4294934783 },
            { position = { 1, 0, -0.5 }, uv = { 1, 1 }, color = 4294934783 },
            { position = { 1, 1, -0.5 }, uv = { 1, 0 }, color = 4294934783 },
            { position = { 1, 1, 0.5 }, uv = { 0, 0 }, color = 4294934783 },
            { position = { -1, 1, 0.5 }, uv = { 0, 1 }, color = 4294934783 },
            { position = { 1, 1, 0.5 }, uv = { 1, 1 }, color = 4294934783 },
            { position = { 1, 1, -0.5 }, uv = { 1, 0 }, color = 4294934783 },
            { position = { -1, 1, -0.5 }, uv = { 0, 0 }, color = 4294934783 },
            { position = { -1, 0, -0.5 }, uv = { 0, 1 }, color = 4294934783 },
            { position = { 1, 0, -0.5 }, uv = { 1, 1 }, color = 4294934783 },
            { position = { 1, 0, 0.5 }, uv = { 1, 0 }, color = 4294934783 },
            { position = { -1, 0, 0.5 }, uv = { 0, 0 }, color = 4294934783 },
        },
        indices = {
            0,
            2,
            1,
            0,
            3,
            2,
            4,
            6,
            5,
            4,
            7,
            6,
            8,
            10,
            9,
            8,
            11,
            10,
            12,
            14,
            13,
            12,
            15,
            14,
            16,
            18,
            17,
            16,
            19,
            18,
            20,
            22,
            21,
            20,
            23,
            22,
        },
        material = 1,
    },
    {
        vertices = {
            {
                position = { -0.4000000059604645, 0.800000011920929, 0 },
                uv = { 0, 1 },
                color = 4294967295,
            },
            {
                position = { 0.4000000059604645, 0.800000011920929, 0 },
                uv = { 1, 1 },
                color = 4294967295,
            },
            { position = { 0.4000000059604645, 0, 0 }, uv = { 1, 0 }, color = 4294967295 },
            { position = { -0.4000000059604645, 0, 0 }, uv = { 0, 0 }, color = 4294967295 },
        },
        indices = { 0, 2, 1, 0, 3, 2 },
        material = 2,
    },
}
local surfaces = {
    {
        width = 2,
        height = 2,
        pixels = { 188, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 188, 255, 255, 255 },
        address_u = "clamp",
        address_v = "repeat",
        cutoff = -1,
    },
    {
        width = 2,
        height = 2,
        pixels = { 255, 0, 0, 255, 0, 128, 0, 128, 0, 0, 0, 0, 255, 255, 255, 255 },
        address_u = "clamp",
        address_v = "repeat",
        cutoff = 128,
    },
}
local nodeLocals: { Matrix } = {
    { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 0, -2, 1 },
    {
        -4.440892098500626e-16,
        0,
        2,
        0,
        0,
        1,
        0,
        0,
        -1,
        0,
        -2.220446049250313e-16,
        0,
        -0.699999988079071,
        0.20000000298023224,
        -0.8999999761581421,
        1,
    },
}
local parents = { 0, 1 }
local parts = { { 1 }, { 2 } }
local names = { "body", "wheel" }
local api = { minimum_sdk = "0.5.0", node_count = 2 }

function api.index(name: string): number
    for index, value in names do
        if name == value then
            return index
        end
    end
    error("Unknown model node: " .. name)
end

function api.local_transforms(): { Matrix }
    local result = {}
    for _, value in nodeLocals do
        table.insert(result, table.clone(value))
    end
    return result
end

function api.create(): Instance
    assert(console.capabilities().sdk >= 1280, "Imported model requires SDK 0.5.0")
    local instance: Instance = { alive = true, meshes = {}, materials = {}, textures = {} }
    for _, surface in surfaces do
        local pixels = data.pixels("rgba8", surface.width, surface.height)
        for index, value in surface.pixels do
            buffer.writeu8(pixels.bytes, index - 1, value)
        end
        local texture =
            gfx.texture({ format = "rgba8", width = surface.width, height = surface.height })
        gfx.upload(
            texture,
            { x = 0, y = 0, width = surface.width, height = surface.height },
            pixels
        )
        local options: MaterialOptions =
            { address_u = surface.address_u :: Address, address_v = surface.address_v :: Address }
        local material = if surface.cutoff < 0
            then g.material(texture, options)
            else g.cutout_material(texture, surface.cutoff, options)
        table.insert(instance.textures, texture)
        table.insert(instance.materials, material)
    end
    for _, primitive in geometry do
        table.insert(instance.meshes, g.textured_mesh(primitive.vertices, primitive.indices))
    end
    return instance
end

function api.draw(pass: console.Pass, instance: Instance, root: Matrix?, locals: { Matrix }?)
    assert(instance.alive, "Model instance is destroyed")
    assert(locals == nil or #locals == #nodeLocals, "Invalid local transform count")
    local world: { Matrix } = {}
    local transforms = locals or nodeLocals
    for index, localModel in transforms do
        local parent = if parents[index] == 0 then (root or g.identity()) else world[parents[index]]
        world[index] = g.multiply(parent, localModel)
        for _, primitive in parts[index] do
            g.draw_textured(
                pass,
                instance.meshes[primitive],
                instance.materials[geometry[primitive].material],
                world[index]
            )
        end
    end
end

function api.destroy(instance: Instance)
    if not instance.alive then
        return
    end
    for _, mesh in instance.meshes do
        g.destroy(mesh)
    end
    for _, material in instance.materials do
        g.destroy(material)
    end
    for _, texture in instance.textures do
        gfx.destroy(texture)
    end
    instance.alive = false
end

return table.freeze(api)

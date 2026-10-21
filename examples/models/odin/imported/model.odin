// Generated model. Reimport geometry; animate local transforms in game code.
package model

import byt "sdk:bytorio"
import data "sdk:data"
import gfx "sdk:gfx"
import g "sdk:gfx3d"

NODE_COUNT :: 2
MINIMUM_SDK :: "0.5.0"
Instance :: struct {
    alive:     bool,
    meshes:    [2]g.Textured_Mesh,
    materials: [2]g.Material,
    textures:  [2]gfx.Texture,
}
names := [NODE_COUNT]string{"body", "wheel"}
parents := [NODE_COUNT]int{-1, 0}
node_locals := [NODE_COUNT]g.Matrix {
    {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 0, -2, 1},
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

index :: proc(name: string) -> int {
    for value, i in names { if name == value { return i } }
    assert(false, "Unknown model node")
    return 0
}

local_transforms :: proc() -> [NODE_COUNT]g.Matrix { return node_locals }

create :: proc() -> Instance {
    assert(byt.VERSION_WORD >= 1280, "Imported model requires SDK 0.5.0")
    instance: Instance

    pixels_0 := data.pixels(.RGBA8, 2, 2)
    bytes_0 := [16]u8{188, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 188, 255, 255, 255}
    copy(pixels_0.bytes, bytes_0[:])
    instance.textures[0] = gfx.texture({.RGBA8, 2, 2})
    gfx.upload(instance.textures[0], {0, 0, 2, 2}, pixels_0)
    data.free_pixels(&pixels_0)
    instance.materials[0] = g.material(
        instance.textures[0],
        {address_u = .Clamp, address_v = .Repeat},
    )


    pixels_1 := data.pixels(.RGBA8, 2, 2)
    bytes_1 := [16]u8{255, 0, 0, 255, 0, 128, 0, 128, 0, 0, 0, 0, 255, 255, 255, 255}
    copy(pixels_1.bytes, bytes_1[:])
    instance.textures[1] = gfx.texture({.RGBA8, 2, 2})
    gfx.upload(instance.textures[1], {0, 0, 2, 2}, pixels_1)
    data.free_pixels(&pixels_1)
    instance.materials[1] = g.cutout_material(
        instance.textures[1],
        128,
        {address_u = .Clamp, address_v = .Repeat},
    )


    vertices_0 := [24]g.Textured_Vertex {
        {{-1, 0, 0.5}, 4294934783, {0, 1}},
        {{1, 0, 0.5}, 4294934783, {1, 1}},
        {{1, 1, 0.5}, 4294934783, {1, 0}},
        {{-1, 1, 0.5}, 4294934783, {0, 0}},
        {{1, 0, -0.5}, 4294934783, {0, 1}},
        {{-1, 0, -0.5}, 4294934783, {1, 1}},
        {{-1, 1, -0.5}, 4294934783, {1, 0}},
        {{1, 1, -0.5}, 4294934783, {0, 0}},
        {{-1, 0, -0.5}, 4294934783, {0, 1}},
        {{-1, 0, 0.5}, 4294934783, {1, 1}},
        {{-1, 1, 0.5}, 4294934783, {1, 0}},
        {{-1, 1, -0.5}, 4294934783, {0, 0}},
        {{1, 0, 0.5}, 4294934783, {0, 1}},
        {{1, 0, -0.5}, 4294934783, {1, 1}},
        {{1, 1, -0.5}, 4294934783, {1, 0}},
        {{1, 1, 0.5}, 4294934783, {0, 0}},
        {{-1, 1, 0.5}, 4294934783, {0, 1}},
        {{1, 1, 0.5}, 4294934783, {1, 1}},
        {{1, 1, -0.5}, 4294934783, {1, 0}},
        {{-1, 1, -0.5}, 4294934783, {0, 0}},
        {{-1, 0, -0.5}, 4294934783, {0, 1}},
        {{1, 0, -0.5}, 4294934783, {1, 1}},
        {{1, 0, 0.5}, 4294934783, {1, 0}},
        {{-1, 0, 0.5}, 4294934783, {0, 0}},
    }
    indices_0 := [36]u32 {
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
    }
    instance.meshes[0] = g.textured_mesh(vertices_0[:], indices_0[:])


    vertices_1 := [4]g.Textured_Vertex {
        {{-0.4000000059604645, 0.800000011920929, 0}, 4294967295, {0, 1}},
        {{0.4000000059604645, 0.800000011920929, 0}, 4294967295, {1, 1}},
        {{0.4000000059604645, 0, 0}, 4294967295, {1, 0}},
        {{-0.4000000059604645, 0, 0}, 4294967295, {0, 0}},
    }
    indices_1 := [6]u32{0, 2, 1, 0, 3, 2}
    instance.meshes[1] = g.textured_mesh(vertices_1[:], indices_1[:])

    instance.alive = true
    return instance
}

draw :: proc(pass: gfx.Pass, instance: ^Instance, root := g.IDENTITY, locals: []g.Matrix = nil) {
    assert(instance.alive, "Model instance is destroyed")
    assert(len(locals) == 0 || len(locals) == NODE_COUNT, "Invalid local transform count")
    world: [NODE_COUNT]g.Matrix
    for i in 0 ..< NODE_COUNT {
        local_model := locals[i] if len(locals) != 0 else node_locals[i]
        parent := root if parents[i] < 0 else world[parents[i]]
        world[i] = g.multiply(parent, local_model)
        switch i {
        case 0:
            g.draw_textured(pass, instance.meshes[0], instance.materials[0], world[0])
        case 1:
            g.draw_textured(pass, instance.meshes[1], instance.materials[1], world[1])
        }
    }
}

destroy :: proc(instance: ^Instance) {
    if !instance.alive { return }
    for mesh in instance.meshes { g.destroy(mesh) }
    for material in instance.materials { g.destroy(material) }
    for texture in instance.textures { gfx.destroy(texture) }
    instance.alive = false
}

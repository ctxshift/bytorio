package main

import console "sdk:console"
import data "sdk:data"
import gfx "sdk:gfx"
import g "sdk:gfx3d"

texture: gfx.Texture
mesh: g.Textured_Mesh
material: g.Material

create_resources :: proc() {
    pixels := data.pixels(.RGBA8, 2, 2)
    defer data.free_pixels(&pixels)
    for &byte in pixels.bytes { byte = 255 }
    texture = gfx.texture({.RGBA8, 2, 2})
    gfx.upload(texture, {0, 0, 2, 2}, pixels)
    vertices := [3]g.Textured_Vertex {
        {{-1, -1, 0.5}, 0xffffffff, {-0.25, 0}},
        {{1, -1, 0.5}, 0xff0000ff, {1.25, 0}},
        {{0, 1, 0.5}, 0xff00ff00, {0.5, 1}},
    }
    indices := [3]u32{0, 1, 2}
    mesh = g.textured_mesh(vertices[:], indices[:])
    material = g.material(texture, {.Repeat, .Clamp})
    for &byte in pixels.bytes { byte = 0 }
    for &vertex in vertices { vertex.uv = {99, 99} }
}

init :: proc() {
    capabilities := console.capabilities()
    assert(capabilities.profile == 4 && capabilities.sdk == 1024 && capabilities.protocol == 6)
    create_resources()
}

update :: proc(_dt: f64) {
    switch console.ticks() {
    case 2:
        pixels := data.pixels(.RGBA8, 2, 2)
        defer data.free_pixels(&pixels)
        for &byte in pixels.bytes { byte = 128 }
        gfx.upload(texture, {0, 0, 2, 2}, pixels)
    case 3:
        g.destroy(material)
        g.destroy(mesh)
        gfx.destroy(texture)
    case 4:
        create_resources()
    }
}

draw :: proc() {
    console.clear(0xff201810)
}

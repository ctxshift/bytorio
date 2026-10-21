package main

import data "sdk:data"
import gfx "sdk:gfx"
import g "sdk:gfx3d"

depth: g.Depth
camera: g.Camera
mesh: g.Textured_Mesh
material: g.Material

init :: proc() {
    depth = g.depth(320, 180)
    projection := g.identity()
    projection[10], projection[11], projection[15] = 0.5, 1, 0
    camera = g.camera({
        view_projection = projection,
        ambient         = 1,
        fog_color       = 0xff000000,
        fog_start       = 1,
        fog_end         = 2,
    })
    pixels := data.pixels(.RGBA8, 1, 4)
    defer data.free_pixels(&pixels)
    for row in 0 ..< 4 {
        pixels.bytes[row * 4 + row % 3] = 255
        pixels.bytes[row * 4 + 3] = 255
    }
    texture := gfx.texture({.RGBA8, 1, 4})
    gfx.upload(texture, {0, 0, 1, 4}, pixels)
    material = g.material(texture, {.Clamp, .Repeat})
    vertices := [3]g.Textured_Vertex {
        {{-1, -1, 1}, 0xffffffff, {0, 0}},
        {{2, -2, 2}, 0xffffffff, {0, 0}},
        {{0, 4, 4}, 0xffffffff, {0, 1.2}},
    }
    indices := [3]u32{0, 1, 2}
    mesh = g.textured_mesh(vertices[:], indices[:])
}

update :: proc(_dt: f64) {  }

draw :: proc() {
    pass := gfx.begin_pass(gfx.screen(), {clear = true, color = 0xff222222})
    g.bind(pass, depth, camera)
    g.draw_textured(pass, mesh, material)
    gfx.end_pass(pass)
    gfx.present(gfx.screen())
}

package main

import console "sdk:console"
import data "sdk:data"
import gfx "sdk:gfx"
import g "sdk:gfx3d"

depth: g.Depth
depth_high: g.Depth
camera: g.Camera
mesh: g.Textured_Mesh
material: g.Material
texture: gfx.Texture

init :: proc() {
    console.display(.Low)
    depth = g.depth(320, 180)
    depth_high = g.depth(640, 360)
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
    texture = gfx.texture({.RGBA8, 1, 4})
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

update :: proc(_dt: f64) {
    console.display(.High if console.button(.Action) else .Low)
    if console.button(.Up) && console.ticks() == 3 {
        pixels := data.pixels(.RGBA8, 1, 1)
        defer data.free_pixels(&pixels)
        pixels.bytes[0], pixels.bytes[3] = 128, 255
        gfx.upload(texture, {0, 1, 1, 1}, pixels)
    }
}

draw :: proc() {
    pass := gfx.begin_pass(gfx.screen(), {clear = true, color = 0xff222222})
    g.bind(pass, depth_high if console.button(.Action) else depth, camera)
    shift := f64(console.ticks()) * 0.001 if console.button(.Right) else 0
    g.draw_textured(pass, mesh, material, g.pose(shift, 0, 0, 0, 1))
    gfx.end_pass(pass)
    gfx.present(gfx.screen())
}

package main

import "core:math"
import byt "sdk:bytorio"
import data "sdk:data"
import gfx "sdk:gfx"
import g "sdk:gfx3d"

ORBIT_VIEWS :: 32
ART_SIZE :: 8

views: [ORBIT_VIEWS]g.Matrix
cameras: [ORBIT_VIEWS]g.Camera
depth_low, depth_high: g.Depth
quad: g.Textured_Mesh
ground, road, kart: g.Mesh
tree, fence, shadow, item: g.Material
view_index: int
smoke, glow: g.Material
particle_tick: int

art :: proc(kind: int) -> g.Material {
    pixels := data.pixels(.RGBA8, ART_SIZE, ART_SIZE)
    defer data.free_pixels(&pixels)
    for y in 0 ..< ART_SIZE {
        for x in 0 ..< ART_SIZE {
            color: u32
            dx, dy := x - 3, y - 3
            switch kind {
            case 0:
                if y < 5 && dx * dx + (y - 2) * (y - 2) <= 9 { color = 0xff4ea653 }
                if y >= 4 && (x == 3 || x == 4) { color = 0xff345e8c }
            case 1:
                if x == 0 || x == 7 || y == 2 || y == 5 { color = 0xffd9ecec }
            case 2:
                if dx * dx + dy * dy <= 10 { color = 0xff202020 }
            case 4, 5:
                if dx * dx + dy * dy <= 10 { color = 0x60403828 if kind == 4 else 0x80206080 }
            case 3:
                if abs(dx) + abs(dy) <= 3 { color = 0xff45c5f4 }
            }
            for channel in 0 ..< 4 {
                pixels.bytes[(y * ART_SIZE + x) * 4 + channel] = u8(
                    (color >> u32(channel * 8)) & 255,
                )
            }
        }
    }
    texture := gfx.texture({.RGBA8, ART_SIZE, ART_SIZE})
    gfx.upload(texture, {0, 0, ART_SIZE, ART_SIZE}, pixels)
    if kind >= 4 {
        return g.effect_material(
            texture,
            {blend = .Additive if kind == 5 else .Alpha, depth_test = true},
        )
    }
    return g.cutout_material(texture)
}

plane :: proc(left, right, near, far, height: f32, color: u32) -> g.Mesh {
    vertices := [4]g.Vertex {
        {{left, height, near}, color},
        {{right, height, near}, color},
        {{right, height, far}, color},
        {{left, height, far}, color},
    }
    indices := [6]u32{0, 2, 1, 0, 3, 2}
    return g.mesh(vertices[:], indices[:])
}

init :: proc() {
    assert(byt.capabilities().profile == 6)
    smoke, glow = art(4), art(5)
    particle_tick = 0
    byt.display(.Low)
    view_index = 0
    depth_low, depth_high = g.depth(320, 180), g.depth(640, 360)
    projection := g.perspective(math.PI / 3, 16.0 / 9, 0.1, 40)
    for index in 0 ..< ORBIT_VIEWS {
        angle := f64(index) * 2 * math.PI / ORBIT_VIEWS
        views[index] = g.look_at(
            {math.sin(angle) * 8, 5, -math.sin(angle + math.PI / 2) * 8},
            {0, 0.6, 2},
        )
        cameras[index] = g.camera(g.camera_defaults(g.multiply(projection, views[index])))
    }
    quad = g.billboard()
    tree, fence, shadow, item = art(0), art(1), art(2), art(3)
    ground = plane(-6, 6, -3, 9, 0, 0xff497b40)
    road = plane(-1.8, 1.8, -3, 9, 0.01, 0xff636572)
    vertices := [8]g.Vertex {
        {{-0.7, 0.15, 1}, 0xff3339a0},
        {{0.7, 0.15, 1}, 0xff3339a0},
        {{0.7, 0.15, 2.3}, 0xff3339a0},
        {{-0.7, 0.15, 2.3}, 0xff3339a0},
        {{-0.7, 0.85, 1}, 0xff5759ef},
        {{0.7, 0.85, 1}, 0xff5759ef},
        {{0.7, 0.85, 2.3}, 0xff5759ef},
        {{-0.7, 0.85, 2.3}, 0xff5759ef},
    }
    indices := [36]u32 {
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
    }
    kart = g.mesh(vertices[:], indices[:])
}

update :: proc(_dt: f64) {
    particle_tick += 1
    byt.display(.High if byt.button(.Action) else .Low)
    if byt.button(.Right) { view_index = (view_index + 1) % ORBIT_VIEWS }
    if byt.button(.Left) { view_index = (view_index + ORBIT_VIEWS - 1) % ORBIT_VIEWS }
}

draw :: proc() {
    pass := gfx.begin_pass(gfx.screen(), {clear = true, color = 0xffb99a79})
    g.bind(pass, depth_high if byt.button(.Action) else depth_low, cameras[view_index])
    g.draw(pass, ground)
    g.draw(pass, road)
    shadow_model := g.identity()
    shadow_model[0], shadow_model[5], shadow_model[6] = 2, 0, 1.8
    shadow_model[9], shadow_model[10] = -1, 0
    shadow_model[12], shadow_model[13], shadow_model[14] = -1, 0.03, 0.7
    g.draw_textured(pass, quad, shadow, shadow_model)
    for position in ([3][3]f64{{-2.2, 0, 0}, {2, 0, 3.5}, {-1, 0, 5}}) {
        g.draw_billboard(pass, quad, tree, {
            position = position,
            size     = {2, 3.4},
            pivot    = {0.5, 0},
            view     = views[view_index],
            mode     = .Upright,
        })
    }
    g.draw_billboard(pass, quad, fence, {
        position = {0, 0, 3.1},
        size     = {4, 1.3},
        pivot    = {0.5, 0},
        view     = views[view_index],
        mode     = .Upright,
    })
    g.draw_billboard(pass, quad, item, {
        position = {0, 2, 1.7},
        size     = {0.8, 0.8},
        pivot    = {0.5, 0.5},
        view     = views[view_index],
        rotation = 0.2,
    })
    // Drawing the opaque kart last tests depth on both sides of cutout artwork.
    g.draw(pass, kart)
    // A fixed ring of 16 persistent particle slots. Age wraps deterministically;
    // resources are shared and no particle creates geometry or material storage.
    // Sort back-to-front in camera space; insertion sort is bounded to 16 slots.
    order: [16]int
    positions: [16][3]f64
    depths: [16]f64
    for i in 0 ..< 16 {
        age := f64((particle_tick + i * 3) % 48) / 48
        positions[i] = {-0.65 + f64(i % 2) * 1.3, 0.3 + age, 1.1 - age * 2.4}
        p := positions[i]
        view := views[view_index]
        depths[i] = f64(view[2]) * p[0] + f64(view[6]) * p[1] + f64(view[10]) * p[2]
        order[i] = i
        for j := i; j > 0 && depths[order[j]] > depths[order[j - 1]]; j -= 1 {
            order[j], order[j - 1] = order[j - 1], order[j]
        }
    }
    for i in order {
        g.draw_billboard(pass, quad, glow if i % 3 == 0 else smoke, {
            position = positions[i],
            size     = {0.55, 0.55},
            pivot    = {0.5, 0.5},
            view     = views[view_index],
        })
    }
    gfx.text(pass, "CUTOUT / SMOKE / ADDITIVE", 6, 6, 0xffffffff)
    gfx.text(pass, "LEFT/RIGHT: ORBIT  ACTION: 640X360", 6, 166, 0xffffffff)
    gfx.end_pass(pass)
    gfx.present(gfx.screen())
}

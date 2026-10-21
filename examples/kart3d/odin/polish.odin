package main

import course "./course"
import kart "./imported"
import tree "./tree"
import "core:math"
import data "sdk:data"
import gfx "sdk:gfx"
import g "sdk:gfx3d"

KART_BODY :: 0
KART_DRIVER :: 1
KART_CAPE :: 2
KART_LOW_WHEEL :: 3
KART_BODY_DETAIL :: 4
KART_DRIVER_DETAIL :: 5
KART_HIGH_WHEEL :: 6
PARTICLE_CAPACITY :: 48
PARTICLE_LIFETIME :: 30
DETAIL_NEAR :: 22.0
DETAIL_FAR :: 26.0

Detail :: enum {
    Auto,
    Low,
    High,
}
Particle :: struct {
    position: [3]f64,
    age:      int,
    glow:     bool,
}

kart_asset: kart.Instance
tree_asset: tree.Instance
kart_surfaces: [8]g.Material
kart_locals: [kart.NODE_COUNT]g.Matrix
detail: Detail
detail_near: [8]bool
view_matrix: g.Matrix
effect_quad: g.Textured_Mesh
dust_surfaces, boost_surfaces: [4]g.Material
ground_shadow, flowers, asphalt: g.Material
roads: [12]g.Textured_Mesh
particles: [PARTICLE_CAPACITY]Particle
particle_cursor: int

make_art :: proc(kind: int, fade := 0) -> g.Material {
    pixels := data.pixels(.RGBA8, 8, 8)
    defer data.free_pixels(&pixels)
    for y in 0 ..< 8 {
        for x in 0 ..< 8 {
            dx, dy := x * 2 - 7, y * 2 - 7
            radius := dx * dx + dy * dy
            color := u32(0)
            if kind == 0 || kind == 1 || kind == 2 {
                alpha := max(0, 64 - radius) * (4 - fade) / 4
                if kind == 2 { alpha /= 2 }
                red, green, blue := alpha * 3 / 4, alpha * 2 / 3, alpha / 2
                if kind == 1 { red, green, blue = alpha / 4, alpha * 3 / 4, alpha }
                if kind == 2 { red, green, blue = alpha / 8, alpha / 8, alpha / 8 }
                color = u32(red | green << 8 | blue << 16 | alpha << 24)
            } else if kind == 3 {
                if (x == 3 || x == 4) && y >= 3 { color = 0xff43924d }
                if radius <= 12 { color = 0xffdcefff }
                if radius <= 2 { color = 0xff35caff }
            } else {
                value := 122 + (x * 13 + y * 7) % 5
                color = 0xff000000 | u32(value) | u32(value + 2) << 8 | u32(value + 5) << 16
            }
            for channel in 0 ..< 4 { pixels.bytes[(y * 8 + x) * 4 + channel] = u8(color >> u32(channel * 8)) }
        }
    }
    texture := gfx.texture({.RGBA8, 8, 8})
    gfx.upload(texture, {0, 0, 8, 8}, pixels)
    if kind == 3 { return g.cutout_material(texture) }
    if kind == 4 { return g.material(texture, {.Repeat, .Repeat}) }
    return g.effect_material(
        texture,
        {blend = .Additive if kind == 1 else .Alpha, depth_test = true},
    )
}

polish_init :: proc() {
    kart_asset = kart.create()
    tree_asset = tree.create()
    kart_surfaces[0] = kart_asset.materials[0]
    for index in 1 ..< 8 {
        pixels := data.pixels(.RGBA8, 16, 16)
        for original, at in KART_ATLAS {
            color := original
            x, y := at % 16, at / 16
            if y < 4 && x < 8 { color = shade(KART_COLORS[index], 100 if x < 4 else 65) }
            for channel in 0 ..< 4 { pixels.bytes[at * 4 + channel] = u8(color >> u32(channel * 8)) }
        }
        texture := gfx.texture({.RGBA8, 16, 16})
        gfx.upload(texture, {0, 0, 16, 16}, pixels)
        data.free_pixels(&pixels)
        kart_surfaces[index] = g.material(texture)
    }
    kart_locals = kart.local_transforms()
    detail = .Auto
    detail_near = {}
    particles = {}
    for &particle in particles { particle.age = PARTICLE_LIFETIME }
    particle_cursor = 0
    effect_quad = g.billboard()
    for i in 0 ..< 4 { dust_surfaces[i], boost_surfaces[i] = make_art(0, i), make_art(1, i) }
    ground_shadow, flowers, asphalt = make_art(2), make_art(3), make_art(4)
    for chunk in 0 ..< 12 {
        vertices: [32]g.Textured_Vertex
        indices: [48]u32
        for segment in 0 ..< 8 {
            i := chunk * 8 + segment
            a, b := course.POINTS[i], course.POINTS[(i + 1) % 96]
            points := [4][3]f64{edge(a, -5.5), edge(a, 5.5), edge(b, 5.5), edge(b, -5.5)}
            uvs := [4][2]f32{{0, 0}, {4, 0}, {4, 1}, {0, 1}}
            for p, corner in points {
                vertices[segment * 4 + corner] = {
                    {f32(p[0]), f32(p[1] + 0.012), f32(p[2])},
                    0xffffffff,
                    uvs[corner],
                }
            }
            for index, at in ([6]u32{0, 2, 1, 0, 3, 2}) { indices[segment * 6 + at] = u32(segment * 4) + index }
        }
        roads[chunk] = g.textured_mesh(vertices[:], indices[:])
    }
}

polish_update :: proc() {
    if s.tick <= 1 {
        for &particle in particles { particle.age = PARTICLE_LIFETIME }
        particle_cursor = 0
    }
    player, _ := sample(s.distance, s.lateral)
    for index in 0 ..< 8 {
        distance := s.distance if index == 0 else s.rivals[index - 1]
        lane := s.lateral if index == 0 else ((index - 1) % 3 - 1) * 370
        p, _ := sample(distance, lane)
        separation :=
            (p[0] - player[0]) * (p[0] - player[0]) + (p[2] - player[2]) * (p[2] - player[2])
        if separation < DETAIL_NEAR * DETAIL_NEAR { detail_near[index] = true }
        if separation > DETAIL_FAR * DETAIL_FAR { detail_near[index] = false }
    }
    for &particle in particles {
        if particle.age < PARTICLE_LIFETIME {
            particle.age += 1
            particle.position[1] += 1.0 / 128
        }
    }
    if s.tick % 3 == 0 && s.speed > 40 && (s.boost > 0 || abs(s.lateral) > 680 || s.drift != 0) {
        side := -80 if (s.tick / 3) % 2 == 0 else 80
        p, _ := sample(s.distance - 300, s.lateral + side)
        p[1] += 0.3
        particles[particle_cursor] = {
            position = p,
            glow     = s.boost > 0 || s.charge > 0,
        }
        particle_cursor = (particle_cursor + 1) % PARTICLE_CAPACITY
    }
}

draw_polished_world :: proc(pass: gfx.Pass, chunk: int) {
    for offset in -3 ..= 3 { g.draw_textured(pass, roads[(chunk + offset + 12) % 12], asphalt) }
    segment := s.distance / 1024
    for offset in -3 ..= 6 {
        at := ((segment / 4 + offset) * 4 + 96) % 96
        for side in ([2]f64{-6.8, 6.8}) {
            p := edge(course.POINTS[at], side)
            g.draw_billboard(pass, effect_quad, flowers, {
                position = p,
                size     = {0.7, 0.7},
                pivot    = {0.5, 0},
                view     = view_matrix,
                mode     = .Upright,
            })
        }
        if at % 8 == 4 {
            p := edge(course.POINTS[at], -9)
            tree.draw(pass, &tree_asset, g.pose(p[0], p[1], p[2], 0, 1))
        }
    }
}

draw_imported_kart :: proc(pass: gfx.Pass, index: int, model: g.Matrix, distance, heading: int) {
    detailed := detail == .High || (detail == .Auto && detail_near[index])
    surface := kart_surfaces[index]
    g.draw_textured(pass, kart_asset.meshes[KART_BODY], surface, model)
    driver := g.multiply(model, g.pose(0, 0, 0, f64(heading) / 2048, 1))
    g.draw_textured(pass, kart_asset.meshes[KART_DRIVER], surface, driver)
    cape := g.multiply(
        driver,
        g.multiply(kart_locals[2], g.pose(0, 0, 0, math.sin(f64(s.tick) / 9) * 0.08, 1)),
    )
    g.draw_textured(pass, kart_asset.meshes[KART_CAPE], surface, cape)
    if detailed {
        g.draw_textured(pass, kart_asset.meshes[KART_BODY_DETAIL], surface, model)
        g.draw_textured(pass, kart_asset.meshes[KART_DRIVER_DETAIL], surface, driver)
    }
    spin := rotation_x(f64(distance % 4096) / 256)
    for node in 3 ..< 7 {
        steer := g.pose(0, 0, 0, f64(heading) / 256 if node < 5 else 0, 1)
        wheel_model := g.multiply(model, g.multiply(kart_locals[node], g.multiply(steer, spin)))
        geometry := KART_HIGH_WHEEL if detailed else KART_LOW_WHEEL
        g.draw_textured(pass, kart_asset.meshes[geometry], surface, wheel_model)
    }
}

draw_effects :: proc(pass: gfx.Pass) {
    // World shadows follow the road plane, without entering the alpha sort.
    for index in 0 ..< 8 {
        distance := s.distance if index == 0 else s.rivals[index - 1]
        lane := s.lateral if index == 0 else ((index - 1) % 3 - 1) * 370
        p, yaw := sample(distance, lane)
        shadow_model := g.Matrix{2.4, 0, 0, 0, 0, 0, 2.8, 0, 0, -1, 0, 0, -1.2, 0.028, -1.4, 1}
        pitch := rotation_x(course.POINTS[distance % 98304 / 1024][7])
        g.draw_textured(
            pass,
            effect_quad,
            ground_shadow,
            g.multiply(g.pose(p[0], p[1], p[2], yaw, 1), g.multiply(pitch, shadow_model)),
        )
    }
    order: [PARTICLE_CAPACITY]int
    depths: [PARTICLE_CAPACITY]f64
    count := 0
    for particle, index in particles {
        if particle.age >= PARTICLE_LIFETIME { continue }
        p := particle.position
        depths[index] =
            f64(view_matrix[2]) * p[0] + f64(view_matrix[6]) * p[1] + f64(view_matrix[10]) * p[2]
        order[count] = index
        for j := count;
            j > 0 && depths[order[j]] > depths[order[j - 1]];
            j -= 1 { order[j], order[j - 1] = order[j - 1], order[j] }
        count += 1
    }
    for index in order[:count] {
        particle := particles[index]
        fade := min(3, particle.age * 4 / PARTICLE_LIFETIME)
        surface := boost_surfaces[fade] if particle.glow else dust_surfaces[fade]
        size := 0.4 + f64(particle.age) / 50
        g.draw_billboard(pass, effect_quad, surface, {
            position = particle.position,
            size     = {size, size},
            pivot    = {0.5, 0.5},
            view     = view_matrix,
        })
    }
}

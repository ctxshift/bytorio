package main

import course "./course"
import "core:math"
import g "sdk:gfx3d"

SKY :: u32(0xffe8b875)
KART_COLORS := [8]u32 {
    0xff3445e8,
    0xff2789e8,
    0xff43b747,
    0xffe36c28,
    0xffcf7740,
    0xff5683dc,
    0xffdddddd,
    0xff62c8f5,
}
chunks: [12]g.Mesh
ground, pickup_mesh, spark: g.Mesh
vertices: [dynamic]g.Vertex
indices: [dynamic]u32

triangle :: proc(a, b, c: [3]f64, color: u32) {
    start := u32(len(vertices))
    for p in ([3][3]f64{a, b, c}) {
        append(&vertices, g.Vertex{{f32(p[0]), f32(p[1]), f32(p[2])}, color})
    }
    append(&indices, start, start + 1, start + 2)
}

quad :: proc(a, b, c, d: [3]f64, color: u32) {
    start := u32(len(vertices))
    for p in ([4][3]f64{a, b, c, d}) {
        append(&vertices, g.Vertex{{f32(p[0]), f32(p[1]), f32(p[2])}, color})
    }
    append(&indices, start, start + 1, start + 2, start, start + 2, start + 3)
}

// Six broad facets keep distant trees, hills and clouds readable.
crown :: proc(x, y, z, w, h, d: f64, color: u32) {
    for side in 0 ..< 6 {
        angle := f64(side) * math.PI / 3
        next := f64(side + 1) * math.PI / 3
        a := [3]f64 {
            x + math.sin(angle + math.PI / 2) * w / 2,
            y + h * 0.45,
            z + math.sin(angle) * d / 2,
        }
        b := [3]f64 {
            x + math.sin(next + math.PI / 2) * w / 2,
            y + h * 0.45,
            z + math.sin(next) * d / 2,
        }
        triangle(a, {x, y + h, z}, b, shade(color, 76 + side * 4))
        triangle(b, {x, y, z}, a, shade(color, 58 + side * 4))
    }
}

pyramid :: proc(x, y, z, w, h, d: f64, color: u32) {
    a := [3]f64{x - w / 2, y, z - d / 2}
    b := [3]f64{x + w / 2, y, z - d / 2}
    c := [3]f64{x + w / 2, y, z + d / 2}
    e := [3]f64{x - w / 2, y, z + d / 2}
    tip := [3]f64{x, y + h, z}
    triangle(a, tip, b, shade(color, 78))
    triangle(b, tip, c, shade(color, 92))
    triangle(c, tip, e, color)
    triangle(e, tip, a, shade(color, 66))
}

shade :: proc(color: u32, factor: int) -> u32 {
    out := u32(0xff000000)
    for shift in ([3]u32{0, 8, 16}) {
        out |= (((color >> shift) & 255) * u32(factor) / 100) << shift
    }
    return out
}

box :: proc(x, y, z, w, h, d: f64, color: u32) {
    a, b, c, e := x - w / 2, x + w / 2, z - d / 2, z + d / 2
    top := y + h
    quad({a, top, c}, {a, top, e}, {b, top, e}, {b, top, c}, color)
    quad({a, y, c}, {b, y, c}, {b, top, c}, {a, top, c}, shade(color, 75))
    quad({b, y, e}, {a, y, e}, {a, top, e}, {b, top, e}, shade(color, 88))
    quad({a, y, e}, {a, y, c}, {a, top, c}, {a, top, e}, shade(color, 68))
    quad({b, y, c}, {b, y, e}, {b, top, e}, {b, top, c}, shade(color, 82))
    quad({a, y, c}, {a, y, e}, {b, y, e}, {b, y, c}, shade(color, 60))
}

finish_mesh :: proc() -> g.Mesh {
    result := g.mesh(vertices[:], indices[:])
    clear(&vertices)
    clear(&indices)
    return result
}

edge :: proc(p: course.Point, offset: f64, lift := 0.0) -> [3]f64 {
    return {p[0] + p[4] * offset, p[1] + lift, p[2] - p[3] * offset}
}

strip :: proc(a, b: course.Point, left, right: f64, color: u32, lift := 0.0) {
    quad(
        edge(a, left, lift),
        edge(b, left, lift),
        edge(b, right, lift),
        edge(a, right, lift),
        color,
    )
}

build_scene :: proc() {
    vertices = make([dynamic]g.Vertex)
    indices = make([dynamic]u32)
    defer delete(vertices)
    defer delete(indices)
    for chunk in 0 ..< 12 {
        for i in chunk * 8 ..< chunk * 8 + 8 {
            a, b := course.POINTS[i], course.POINTS[(i + 1) % 96]
            strip(a, b, -5.5, 5.5, 0xff858689)
            curb := u32(0xffeeeef4) if i % 2 == 0 else u32(0xff4347da)
            strip(a, b, -6.1, -5.5, curb)
            strip(a, b, 5.5, 6.1, curb)
            grass := u32(0xff399e58) if i % 2 == 0 else u32(0xff359452)
            strip(a, b, -12, -6.1, grass)
            strip(a, b, 6.1, 12, grass)
            if i % 4 < 2 {
                strip(a, b, -0.08, 0.08, 0xffcfe5ec, 0.025)
            }
            if i % 8 == 4 {
                p := edge(a, 9)
                box(p[0], p[1], p[2], 0.55, 2, 0.55, 0xff486283)
                crown(p[0], p[1] + 1.3, p[2], 3.8, 4.0, 3.8, 0xff38a367)
            }
            if i % 4 == 0 {
                for side in ([2]f64{-7.2, 7.2}) {
                    p := edge(a, side)
                    box(p[0], p[1], p[2], 0.28, 0.8, 0.28, 0xffe8f0f1)
                }
            }
            if i == 0 {
                for x in 0 ..< 10 {
                    strip(
                        a,
                        b,
                        -5.5 + f64(x) * 1.1,
                        -5.5 + f64(x + 1) * 1.1,
                        0xffeeeeee if x % 2 == 0 else 0xff25252c,
                        0.03,
                    )
                }
                p := edge(a, -6.5)
                q := edge(a, 6.5)
                box(p[0], p[1], p[2], 0.5, 4.5, 0.5, 0xffeeeeee)
                box(q[0], q[1], q[2], 0.5, 4.5, 0.5, 0xffeeeeee)
                // The starting tangent is almost along +X: an overhead banner spans the road.
                box(a[0], a[1] + 4, a[2], 0.7, 0.7, 14, 0xff4894ec)
            }
        }
        chunks[chunk] = finish_mesh()
    }
    quad({-160, -3, -160}, {-160, -3, 160}, {160, -3, 160}, {160, -3, -160}, 0xff39834b)
    for hill in 0 ..< 4 {
        angle := f64(hill) * math.PI / 2 + 0.35
        crown(math.sin(angle) * 16, -3, math.sin(angle + math.PI / 2) * 16, 27, 10, 22, 0xff4ca46d)
    }
    for cloud in 0 ..< 6 {
        angle := f64(cloud) * math.PI / 3
        crown(
            math.sin(angle) * 68,
            19 + f64(cloud % 2) * 3,
            math.sin(angle + math.PI / 2) * 68,
            19,
            4,
            7,
            0xfffaf5ec,
        )
    }
    // An original hilltop keep is visible from several bends of the course.
    box(0, 1, 0, 9, 8, 7, 0xffb5c5cb)
    box(0, 8, 0, 4, 5, 4, 0xffc8d4d8)
    pyramid(0, 13, 0, 5.2, 3.2, 5.2, 0xff3447c5)
    for side in ([2]f64{-1, 1}) {
        box(side * 5, 1, 1, 3, 9, 3, 0xffb5c5cb)
        pyramid(side * 5, 10, 1, 4, 3.5, 4, 0xff3447c5)
        box(side * 2.7, 9, 0, 1.3, 1.2, 7, 0xffd3dce0)
        quad(
            {side * 5 - 0.35, 6, 2.51},
            {side * 5 + 0.35, 6, 2.51},
            {side * 5 + 0.35, 7.5, 2.51},
            {side * 5 - 0.35, 7.5, 2.51},
            0xff424750,
        )
    }
    quad({-1.1, 1, 3.51}, {1.1, 1, 3.51}, {1.1, 4.4, 3.51}, {-1.1, 4.4, 3.51}, 0xff405c78)
    triangle({0, 16.1, 0}, {0, 17.8, 0}, {2.5, 17.1, 0}, 0xff3a4de0)
    ground = finish_mesh()
    box(0, 0, 0, 0.65, 0.65, 0.65, 0xff52dcf5)
    box(0, 0.12, 0.34, 0.2, 0.4, 0.02, 0xffeeeeee)
    pickup_mesh = finish_mesh()
    box(0, 0, 0, 0.13, 0.15, 0.4, 0xff42cfff)
    spark = finish_mesh()

}

sample :: proc(distance: int, lane := 0) -> (p: [3]f64, yaw: f64) {
    at := ((distance % 98304) + 98304) % 98304
    index := at / 1024
    a, b := course.POINTS[index], course.POINTS[(index + 1) % 96]
    fraction := f64(at % 1024) / 1024
    p = {
        a[0] + (b[0] - a[0]) * fraction,
        a[1] + (b[1] - a[1]) * fraction,
        a[2] + (b[2] - a[2]) * fraction,
    }
    p[0] += (a[4] + (b[4] - a[4]) * fraction) * f64(lane) / 128
    p[2] -= (a[3] + (b[3] - a[3]) * fraction) * f64(lane) / 128
    turn := b[6] - a[6]
    if turn > math.PI { turn -= 2 * math.PI }
    if turn < -math.PI { turn += 2 * math.PI }
    yaw = a[6] + turn * fraction
    return
}

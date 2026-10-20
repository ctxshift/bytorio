package main

import console "sdk:console"
import gfx "sdk:gfx"
import g "sdk:gfx3d"

room, prop, checker: g.Voxel
actors: [2]g.Voxel
depth_low, depth_high: g.Depth
ortho, perspective: g.Camera
pyramid: g.Mesh
palette: gfx.Palette
tick: u32
BACKGROUND :: u32(0xff291b16)

init :: proc() {
    assert(console.capabilities().profile == 3)
    tick = 0
    console.display(.Low)
    depth_low = g.depth(320, 180)
    depth_high = g.depth(640, 360)
    colors: [256]u32
    colors[1] = 0xff699047
    colors[2] = 0xff735e54
    colors[3] = 0xff977c63
    colors[4] = 0xff55b8fa
    colors[5] = 0xffd2d7ee
    colors[6] = 0xffde8d44
    colors[7] = 0xff754ed3
    colors[8] = 0xffa5e5ff
    palette = gfx.palette(colors[:])
    cells: [12 * 6 * 12]u8
    for z in 0 ..< 12 {
        for y in 0 ..< 6 {
            for x in 0 ..< 12 {
                cell := u8(0)
                if y == 0 {
                    cell = 1
                }

                if (x == 0 || z == 11) && y < 5 {
                    cell = u8(2 + (x + z + y) % 2)
                }

                if z == 11 && (x == 5 || x == 6) && y > 0 && y < 4 {
                    cell = 0
                }

                cells[(z * 6 + y) * 12 + x] = cell
            }
        }
    }

    room = g.voxel(12, 6, 12, palette, cells[:])
    block: [4 * 4 * 4]u8
    for &cell, i in block {
        cell = u8(4 + i % 3)
    }

    prop = g.voxel(4, 4, 4, palette, block[:])
    noise: [16 * 16 * 16]u8
    for z in 0 ..< 16 {
        for y in 0 ..< 16 {
            for x in 0 ..< 16 {
                noise[(z * 16 + y) * 16 + x] =
                    u8(4 + (x + y + z) % 3) if (x + y + z) % 2 == 0 else 0
            }
        }
    }

    checker = g.voxel(16, 16, 16, palette, noise[:])
    for frame in 0 ..< 2 {
        actor: [4 * 6 * 3]u8
        for z in 0 ..< 3 {
            for y in 0 ..< 6 {
                for x in 0 ..< 4 {
                    cell := u8(0)
                    if x == 1 || x == 2 {
                        cell = 4 if y >= 4 else 6
                    }

                    if y == 2 + frame && (x == 0 || x == 3) {
                        cell = 4
                    }

                    if z == 0 && y == 4 && (x == 1 || x == 2) {
                        cell = 2
                    }

                    actor[(z * 6 + y) * 4 + x] = cell
                }
            }
        }

        actors[frame] = g.voxel(4, 6, 3, palette, actor[:])
    }

    view := g.look_at({20, 18, -25}, {6, 1, 6})
    ortho = g.camera({
        view_projection = g.multiply(g.orthographic(-14.222222, 14.222222, -8, 8, 0.1, 100), view),
        light           = {0.3, 0.8, -0.5},
        ambient         = 0.45,
        fog_color       = BACKGROUND,
        fog_start       = 0.6,
        fog_end         = 1,
    })
    perspective = g.camera({
        view_projection = g.multiply(g.perspective(0.65, 16.0 / 9.0, 1, 100), view),
        light           = {0.3, 0.8, -0.5},
        ambient         = 0.45,
        fog_color       = BACKGROUND,
        fog_start       = 0.985,
        fog_end         = 1,
    })
    vertices := [5]g.Vertex {
        {
            {0, 0, 0},
            0xff6b72ed,
        },
        {
            {4, 0, 0},
            0xff6b72ed,
        },
        {
            {4, 0, 4},
            0xff6b72ed,
        },
        {
            {0, 0, 4},
            0xff6b72ed,
        },
        {
            {2, 5, 2},
            0xffb9ceff,
        },
    }

    indices := [18]u32{0, 1, 4, 1, 2, 4, 2, 3, 4, 3, 0, 4, 0, 3, 2, 0, 2, 1}

    pyramid = g.mesh(vertices[:], indices[:])
}

update :: proc(_dt: f64) {
    tick += 1
    console.display(.High if console.button(.Action) else .Low)
    if console.button(.Down) {
        cell := [1]u8{u8(tick % 2) * 3}

        g.edit(room, 5, 3, 11, 1, 1, 1, cell[:])
    }
}

draw :: proc() {
    screen := gfx.screen()
    pass := gfx.begin_pass(screen, {
        clear = true,
        color = BACKGROUND,
    })
    high := console.button(.Action)
    view := perspective if console.button(.Right) else ortho
    g.bind(pass, depth_high if high else depth_low, view)
    g.draw(pass, room)
    g.draw(pass, actors[(tick / 15) % 2], g.pose(3, 1, 3, 0, 0.65))
    g.draw(pass, pyramid, g.pose(7, 1, 6, 0, 0.7))
    angle := f64(tick) * 0.015
    g.draw(pass, prop, g.pose(7, 2, 2, angle, 0.65))
    if console.button(.Up) {
        g.draw(pass, checker, g.pose(2, 2, 4, angle, 0.35))
    }

    if console.button(.Left) {
        for z in 0 ..< 8 {
            for x in 0 ..< 8 {
                g.draw(pass, prop, g.pose(1 + f64(x) * 1.2, 1, 1 + f64(z) * 1.2, angle, 0.2))
            }
        }
    }

    scale := f64(2) if high else f64(1)
    gfx.transform(pass, {scale, 0, 0, scale, 0, 0})
    gfx.rect(pass, 8, 8, 304, 19, 0xff382925)
    gfx.text(pass, "VOXEL GARDEN / SHARED 3D", 15, 14, 0xffdceeff)
    gfx.text(pass, "DOWN:EDIT UP:STRESS LEFT:64 PROPS", 12, 157, 0xffdceeff)
    gfx.text(pass, "RIGHT:PERSPECTIVE ACTION:640X360", 12, 168, 0xffdceeff)
    gfx.end_pass(pass)
    gfx.present(screen)
}

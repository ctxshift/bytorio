package main

import "core:math"
import console "sdk:console"
import gfx "sdk:gfx"
import g "sdk:gfx3d"

FACE_BYTES :: 13
FACES_PER_CHUNK :: 512
BACKGROUND :: u32(0xffc5ad94)
// Populated by console-build.mjs from the preserved scene's surface field.
scene := []u8{}
DECODE_UPDATES :: 0
decode_wait: int
meshes: [64]g.Mesh
mesh_count, loaded, tick, face_offset, world_faces, rabbit_faces: int
rabbit: g.Mesh
depth_low, depth_high: g.Depth
camera: g.Camera
high: bool

read16 :: proc(at: int) -> int {
    return int(scene[at]) | int(scene[at + 1]) << 8
}

signed16 :: proc(at: int) -> f32 {
    return f32(i16(u16(read16(at))))
}

read32 :: proc(at: int) -> u32 {
    return u32(read16(at)) | u32(read16(at + 2)) << 16
}

upload :: proc(first, count: int) -> g.Mesh {
    vertices := make([]g.Vertex, count * 4)
    indices := make([]u32, count * 6)
    defer delete(vertices)
    defer delete(indices)
    for i in 0 ..< count {
        at := face_offset + (first + i) * FACE_BYTES
        tag := int(scene[at])
        axis := tag % 4
        axes := [2]int{1, 2} if axis == 0 else ([2]int{0, 2} if axis == 1 else [2]int{0, 1})
        plane, x, y := signed16(at + 1), signed16(at + 3), signed16(at + 5)
        width, height := f32(read16(at + 7)), f32(read16(at + 9))
        color := read32(12 + read16(at + 11) * 4)
        corners := [4][2]f32{{0, 0}, {width, 0}, {width, height}, {0, height}}
        for corner, j in corners {
            p: [3]f32
            p[axis] = plane
            p[axes[0]] = x + corner[0]
            p[axes[1]] = y + corner[1]
            vertices[i * 4 + j] = {p, color}
        }
        reverse := (tag >= 4) != (axis == 1)
        order := [6]u32{0, 2, 1, 0, 3, 2} if reverse else [6]u32{0, 1, 2, 0, 2, 3}
        for index, j in order {
            indices[i * 6 + j] = u32(i * 4) + index
        }
    }
    return g.mesh(vertices, indices)
}

update_camera :: proc() {
    yaw := f64(tick) * 0.004 if console.button(.Right) else 0
    s, c := math.sin(yaw), math.sin(yaw + math.PI / 2)
    fx := -0.09692560046268578 * c - 0.8077133371890481 * s
    fy := -0.5815536027761147
    fz := 0.09692560046268578 * s - 0.8077133371890481 * c
    length := math.sqrt(fx * fx + fz * fz)
    rx, rz := -fz / length, fx / length
    ux, uy, uz := -rz * fy, rz * fx - rx * fz, rx * fy
    tx := f64(tick) * 0.07 if console.button(.Left) else 0
    view := g.Matrix {
        f32(rx),
        f32(ux),
        f32(fx),
        0,
        0,
        f32(uy),
        f32(fy),
        0,
        f32(rz),
        f32(uz),
        f32(fz),
        0,
        f32(-rx * tx),
        f32(-ux * tx - uy * 24),
        f32(300 - fx * tx - fy * 24),
        1,
    }
    camera = g.camera({
        view_projection = g.multiply(g.orthographic(-90, 90, -50.625, 50.625, 0.1, 1000), view),
        ambient         = 1,
        fog_color       = BACKGROUND,
        fog_start       = 0.999,
        fog_end         = 1,
    })
}

init :: proc() {
    world_faces, rabbit_faces = int(read32(0)), int(read32(4))
    face_offset = 12 + int(read32(8)) * 4
    assert(len(scene) == face_offset + (world_faces + rabbit_faces) * FACE_BYTES)
    loaded, tick, mesh_count = 0, 0, 0
    // Mirror the Luau fixture decoder's loading schedule for exact replays.
    decode_wait = DECODE_UPDATES
    depth_low, depth_high = g.depth(320, 180), g.depth(640, 360)
    update_camera()
}

update :: proc(dt: f64) {
    high = console.button(.Action)
    console.display(.High if high else .Low)
    if decode_wait > 0 {
        decode_wait -= 1
        return
    }
    if loaded < world_faces {
        count := min(FACES_PER_CHUNK, world_faces - loaded)
        meshes[mesh_count] = upload(loaded, count)
        mesh_count += 1
        loaded += count
    } else if loaded == world_faces {
        rabbit = upload(world_faces, rabbit_faces)
        loaded += rabbit_faces
    } else {
        tick += 1
    }
    g.destroy(camera)
    update_camera()
}

draw :: proc() {
    screen := gfx.screen()
    pass := gfx.begin_pass(screen, {clear = true, color = BACKGROUND})
    if loaded > world_faces {
        g.bind(pass, depth_high if high else depth_low, camera)
        for mesh in meshes[:mesh_count] {
            g.draw(pass, mesh)
        }
        step := math.sin(f64(tick) * 0.03) * 2 if console.button(.Up) else 0
        g.draw(pass, rabbit, g.pose(-4 + step, 8, 19, 0, 1))
    }
    gfx.end_pass(pass)
    gfx.present(screen)
}

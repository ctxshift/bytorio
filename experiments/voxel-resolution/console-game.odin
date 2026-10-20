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
walk_offset: int
WALK_WIDTH :: 157
WALK_HEIGHT :: 137
FORWARD_HEADING :: 0.11942892601833846
rabbit_x, rabbit_y, rabbit_z, rabbit_angle: f64
yaw, pan_x, pan_z: f64
qualification_replay, camera_ready: bool
last_projection: g.Matrix

reset_motion :: proc() {
    rabbit_x, rabbit_y, rabbit_z, rabbit_angle = -4, 8, 19, 0
    yaw, pan_x, pan_z = 0, 0, 0
}

walk_height :: proc(x, z: f64) -> f64 {
    ix, iz := int(math.floor(x + 0.5)) + 78, int(math.floor(z + 0.5)) + 68
    if ix < 0 || ix >= WALK_WIDTH || iz < 0 || iz >= WALK_HEIGHT { return -1 }
    return f64(scene[walk_offset + iz * WALK_WIDTH + ix]) - 1
}

move_rabbit :: proc(x, z: f64) {
    height := walk_height(x, z)
    if height < 0 || abs(height - rabbit_y) > 2 { return }
    for dx in ([2]f64{-1, 1}) {
        for dz in ([2]f64{-1, 1}) {
            edge := walk_height(x + dx, z + dz)
            if edge < 0 || abs(edge - height) > 2 { return }
        }
    }
    rabbit_x, rabbit_y, rabbit_z = x, height, z
}

axis :: proc(positive, negative: console.Button) -> f64 {
    return f64(int(console.button(positive)) - int(console.button(negative)))
}

update_controls :: proc(dt: f64) {
    if console.pressed(.Reset) { reset_motion() }
    yaw += dt * axis(.RotateRight, .RotateLeft) * 0.7
    yaw -= math.floor((yaw + math.PI) / (2 * math.PI)) * 2 * math.PI
    pan_x = clamp(pan_x + dt * axis(.PanRight, .PanLeft) * 7, -12, 12)
    pan_z = clamp(pan_z + dt * axis(.PanDown, .PanUp) * 7, -12, 12)
    dx, dz := axis(.MoveRight, .MoveLeft), axis(.MoveDown, .MoveUp)
    length := math.sqrt(dx * dx + dz * dz)
    if length == 0 { return }
    dx /= length
    dz /= length
    s, c := math.sin(yaw), math.sin(yaw + math.PI / 2)
    fx := -0.09692560046268578 * c - 0.8077133371890481 * s
    fz := 0.09692560046268578 * s - 0.8077133371890481 * c
    horizontal := math.sqrt(fx * fx + fz * fz)
    mx, mz := (-fz * dx - fx * dz) / horizontal, (fx * dx - fz * dz) / horizontal
    move_rabbit(rabbit_x + mx * dt * 12, rabbit_z)
    move_rabbit(rabbit_x, rabbit_z + mz * dt * 12)
    sign := -1.0 if dx < 0 else 1.0 if dx > 0 else 0.0
    facing :=
        sign * math.PI / 2 if dz == 0 else sign * math.PI / 4 if dz > 0 else sign * 3 * math.PI / 4 if dx != 0 else math.PI
    rabbit_angle = FORWARD_HEADING + yaw + facing
}

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
    angle := (f64(tick) * 0.004 if console.button(.Right) else 0) if qualification_replay else yaw
    s, c := math.sin(angle), math.sin(angle + math.PI / 2)
    fx := -0.09692560046268578 * c - 0.8077133371890481 * s
    fy := -0.5815536027761147
    fz := 0.09692560046268578 * s - 0.8077133371890481 * c
    length := math.sqrt(fx * fx + fz * fz)
    rx, rz := -fz / length, fx / length
    ux, uy, uz := -rz * fy, rz * fx - rx * fz, rx * fy
    tx :=
        (f64(tick) * 0.07 if console.button(.Left) else 0) if qualification_replay else pan_x + (rabbit_x + 4) * 0.3
    tz := 0.0 if qualification_replay else pan_z + (rabbit_z - 19) * 0.3
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
        f32(-rx * tx - rz * tz),
        f32(-ux * tx - uy * 24 - uz * tz),
        f32(300 - fx * tx - fy * 24 - fz * tz),
        1,
    }
    projection := g.multiply(g.orthographic(-90, 90, -50.625, 50.625, 0.1, 1000), view)
    if camera_ready && projection == last_projection { return }
    if camera_ready { g.destroy(camera) }
    camera = g.camera({
        view_projection = projection,
        ambient         = 1,
        fog_color       = BACKGROUND,
        fog_start       = 0.999,
        fog_end         = 1,
    })
    last_projection, camera_ready = projection, true
}

init :: proc() {
    world_faces, rabbit_faces = int(read32(0)), int(read32(4))
    face_offset = 12 + int(read32(8)) * 4
    walk_offset = face_offset + (world_faces + rabbit_faces) * FACE_BYTES
    assert(len(scene) == walk_offset + WALK_WIDTH * WALK_HEIGHT)
    loaded, tick, mesh_count = 0, 0, 0
    // Mirror the Luau fixture decoder's loading schedule for exact replays.
    decode_wait = DECODE_UPDATES
    reset_motion()
    console.debug_position(rabbit_x, rabbit_z)
    qualification_replay, camera_ready = false, false
    depth_low, depth_high = g.depth(320, 180), g.depth(640, 360)
    update_camera()
}

update :: proc(dt: f64) {
    // Legacy-only masks preserve the fixed qualification camera replay.
    qualification_replay =
        console.all_buttons() == console.buttons() && console.buttons() & 15 != 0
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
        if !qualification_replay { update_controls(dt) }
        console.debug_position(rabbit_x, rabbit_z)
    }
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
        if qualification_replay {
            step := math.sin(f64(tick) * 0.03) * 2 if console.button(.Up) else 0
            g.draw(pass, rabbit, g.pose(-4 + step, 8, 19, 0, 1))
        } else {
            g.draw(pass, rabbit, g.pose(rabbit_x, rabbit_y, rabbit_z, rabbit_angle, 1))
        }
    }
    gfx.end_pass(pass)
    gfx.present(screen)
}

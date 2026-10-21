package main

import course "./course"
import race "./race"
import "core:fmt"
import "core:math"
import byt "sdk:bytorio"
import gfx "sdk:gfx"
import g "sdk:gfx3d"

s: race.State
depths: [2]g.Depth
camera: g.Camera
eye: [3]f64
high: bool

camera_update :: proc(first := false) {
    p, yaw := sample(s.distance, s.lateral)
    desired := [3]f64 {
        p[0] - math.sin(yaw) * 5.8,
        p[1] + 3.0,
        p[2] - math.sin(yaw + math.PI / 2) * 5.8,
    }
    for value, i in desired {
        eye[i] = value if first else math.floor((eye[i] + (value - eye[i]) / 5) * 256) / 256
    }
    target, _ := sample(s.distance + 1300, s.lateral)
    target[1] += 0.9
    if !first { g.destroy(camera) }
    view_matrix = g.look_at(eye, target)
    camera = g.camera({
        view_projection = g.multiply(
            g.perspective(55 * math.PI / 180, 16.0 / 9, 0.2, 95),
            view_matrix,
        ),
        ambient         = 1,
        fog_color       = SKY,
        fog_start       = 0.996,
        fog_end         = 1,
    })
}

init :: proc() {
    s = race.new()
    high = false
    byt.display(.Low)
    depths = {g.depth(320, 180), g.depth(640, 360)}
    build_scene()
    polish_init()
    polish_update()
    camera_update(true)
}

update :: proc(_dt: f64) {
    events := s.events
    race.step(&s, int(byt.all_buttons()))
    if byt.pressed(.RotateLeft) {
        if byt.button(.Action) { detail = Detail((int(detail) + 1) % 3) } else { high = !high }
    }
    byt.display(.High if high else .Low)
    if s.events > events { byt.sound() }
    camera_update()
    polish_update()
    byt.debug_position(f64(s.distance % race.LAP) / 1024, f64(s.lateral) / 128)
}

rotation_x :: proc(angle: f64) -> g.Matrix {
    c, v := f32(math.sin(angle + math.PI / 2)), f32(math.sin(angle))
    return {1, 0, 0, 0, 0, c, v, 0, 0, -v, c, 0, 0, 0, 0, 1}
}

draw_kart :: proc(pass: gfx.Pass, index, distance, lane: int, heading := 0, hop := 0) {
    p, yaw := sample(distance, lane)
    player, _ := sample(s.distance, s.lateral)
    if index != 0 &&
       (p[0] - player[0]) * (p[0] - player[0]) + (p[2] - player[2]) * (p[2] - player[2]) >
           75 * 75 { return }
    lift := math.sin(f64(hop) * math.PI / 12) * 0.55
    pitch := rotation_x(
        course.POINTS[((distance % race.LAP) + race.LAP) % race.LAP / race.SEGMENT][7],
    )
    model := g.multiply(g.pose(p[0], p[1] + 0.04 + lift, p[2], yaw + f64(heading) / 512, 1), pitch)
    draw_imported_kart(pass, index, model, distance, heading)
    if index == 0 && (s.charge > 0 || s.boost > 0) {
        for x in ([2]f64{-0.85, 0.85}) { g.draw(pass, spark, g.multiply(model, g.pose(x, 0.3, -1.3, 0, 1 + f64(s.charge)))) }
    }
}

label_buffer: [96]u8
label :: proc(pattern: string, args: ..any) -> string {
    return fmt.bprintf(label_buffer[:], pattern, ..args)
}

draw :: proc() {
    pass := gfx.begin_pass(gfx.screen(), {clear = true, color = SKY})
    g.bind(pass, depths[1 if high else 0], camera)
    g.draw(pass, ground)
    chunk := (s.distance / race.SEGMENT) % 96 / 8
    for offset in -3 ..= 3 { g.draw(pass, chunks[(chunk + offset + 12) % 12]) }
    draw_polished_world(pass, chunk)
    for i in 1 ..< 8 { draw_kart(pass, i, s.rivals[i - 1], ((i - 1) % 3 - 1) * 370) }
    draw_kart(pass, 0, s.distance, s.lateral, s.heading + (s.drift * 45), s.hop)
    next_pickup := (s.distance / (race.SEGMENT * 12) + 1) * (race.SEGMENT * 12)
    for lane in ([3]int{-333, 0, 333}) {
        p, _ := sample(next_pickup, lane)
        g.draw(pass, pickup_mesh, g.pose(p[0], p[1] + 1, p[2], f64(s.tick) / 50, 1))
    }
    draw_effects(pass)
    draw_hud(pass)
    names := [3]string{"AUTO LOD", "LOW DETAIL", "HIGH DETAIL"}
    gfx.text(pass, names[int(detail)], 8, 27, HUD_WHITE)
    gfx.end_pass(pass)
    gfx.present(gfx.screen())
}

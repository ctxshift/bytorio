package main

import model "./imported"
import "core:math"
import console "sdk:console"
import gfx "sdk:gfx"
import g "sdk:gfx3d"

instance: model.Instance
transforms, base: [model.NODE_COUNT]g.Matrix
depth_low, depth_high: g.Depth
camera: g.Camera
tick: int

init :: proc() {
    tick = 0
    console.display(.Low)
    depth_low, depth_high = g.depth(320, 180), g.depth(640, 360)
    view := g.look_at({5, 3, -8}, {1, 0.5, -2})
    camera = g.camera(
        g.camera_defaults(g.multiply(g.perspective(math.PI / 3, 16.0 / 9, 0.1, 40), view)),
    )
    instance = model.create()
    base, transforms = model.local_transforms(), model.local_transforms()
}

update :: proc(_dt: f64) {
    console.display(.High if console.button(.Action) else .Low)
    if console.button(.Down) {
        model.destroy(&instance)
    } else if !instance.alive {
        instance = model.create()
    }
    if console.button(.Right) {
        tick += 1
    } else if console.button(.Left) {
        tick -= 1
    }
    body, wheel := model.index("body"), model.index("wheel")
    transforms[body] = g.multiply(base[body], g.pose(0, 0, 0, f64(tick) * 0.125, 1))
    transforms[wheel] = g.multiply(base[wheel], g.pose(0, 0, 0, f64(tick) * 0.25, 1))
}

draw :: proc() {
    pass := gfx.begin_pass(gfx.screen(), {clear = true, color = 0xff322015})
    g.bind(pass, depth_high if console.button(.Action) else depth_low, camera)
    if instance.alive {
        model.draw(pass, &instance, locals = transforms[:])
    }
    gfx.text(pass, "IMPORTED RIGID MODEL", 6, 6, 0xffffffff)
    gfx.text(pass, "ARROWS: TURN / DOWN: RELEASE / ACTION: HD", 6, 166, 0xffffffff)
    gfx.end_pass(pass)
    gfx.present(gfx.screen())
}

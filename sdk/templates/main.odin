package main
import byt "sdk:bytorio"
x, y: f64
init :: proc() {

    x, y = 40, 40
    byt.sound()
}
update :: proc(dt: f64) {
    if byt.button(.Left) {

        x -= 90 * dt
    }
    if byt.button(.Right) {

        x += 90 * dt
    }
    if byt.button(.Up) {

        y -= 90 * dt
    }
    if byt.button(.Down) {

        y += 90 * dt
    }
    active, px, py := byt.pointer()
    if active {

        x, y = px - 8, py - 8
    }
    w, h := byt.size()
    x, y = clamp(x, 0, f64(w - 16)), clamp(y, 20, f64(h - 16))
    if byt.pressed(.Action) {

        byt.sound()
    }
}
draw :: proc() {
    byt.clear(byt.rgb(23, 32, 46))
    byt.sprite(0, int(x), int(y))
    byt.text("__STARTER_MESSAGE__", 8, 7, byt.rgb(244, 236, 214))
}

package main
import "core:math"
import byt "sdk:bytorio"
random, edges: u32
px, py: f64
init :: proc() {

    random, edges = 0, 0
    byt.seed(123)
    byt.sound()
}
update :: proc(dt: f64) {
    assert(dt == 1.0 / 60.0)
    if byt.pressed(.Action) {

        edges += 1
        byt.sound()
    }
    if byt.released(.Action) {

        edges += 10
    }
    active, x, y := byt.pointer()
    px, py = 0, 0
    if active {

        px, py = x, y
    }
    random = byt.random_u32() % 1000
    if byt.ticks() == 20 || byt.ticks() == 60 {

        byt.display(.Low)
    }
    if byt.ticks() == 40 {

        byt.display(.High)
    }
    byt.debug_position(f64(random), f64(edges))
}
draw :: proc() {
    byt.clear(byt.rgb(23, 32, 46))
    byt.rect(-2, -2, 8, 8, byt.rgb(255, 0, 0))
    byt.rect(12, 12, 0, 20, byt.rgb(0, 0, 0))
    byt.sprite(0, -4, 8, 2)
    byt.sprite_size(0, 60, 30, 7 + int(byt.ticks() % 25), 11)
    byt.text("SDK\nPARITY", 20, 50, byt.rgb(255, 255, 255))
    byt.rect(int(math.floor(px)), int(math.floor(py)), 3, 3, byt.rgb(0, 255, 0))
    if byt.button(.Right) {

        byt.rect(40, 90, 8, 8, byt.rgb(0, 0, 255))
    }
}

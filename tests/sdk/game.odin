package main
import "core:math"
import console "sdk:console"
random, edges: u32
px, py: f64
init :: proc() {

    random, edges = 0, 0
    console.seed(123)
    console.sound()
}
update :: proc(dt: f64) {
    assert(dt == 1.0 / 60.0)
    if console.pressed(.Action) {

        edges += 1
        console.sound()
    }
    if console.released(.Action) {

        edges += 10
    }
    active, x, y := console.pointer()
    px, py = 0, 0
    if active {

        px, py = x, y
    }
    random = console.random_u32() % 1000
    if console.ticks() == 20 || console.ticks() == 60 {

        console.display(.Low)
    }
    if console.ticks() == 40 {

        console.display(.High)
    }
    console.debug_position(f64(random), f64(edges))
}
draw :: proc() {
    console.clear(console.rgb(23, 32, 46))
    console.rect(-2, -2, 8, 8, console.rgb(255, 0, 0))
    console.rect(12, 12, 0, 20, console.rgb(0, 0, 0))
    console.sprite(0, -4, 8, 2)
    console.sprite_size(0, 60, 30, 7 + int(console.ticks() % 25), 11)
    console.text("SDK\nPARITY", 20, 50, console.rgb(255, 255, 255))
    console.rect(int(math.floor(px)), int(math.floor(py)), 3, 3, console.rgb(0, 255, 0))
    if console.button(.Right) {

        console.rect(40, 90, 8, 8, console.rgb(0, 0, 255))
    }
}

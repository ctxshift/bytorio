package main
import "core:math"
import byt "sdk:bytorio"
random, edges: u32
px, py: f64
input_probe: bool
init :: proc() {

    random, edges = 0, 0
    input_probe = false
    byt.seed(123)
    byt.sound()
}
update :: proc(dt: f64) {
    assert(dt == 1.0 / 60.0)
    tick := byt.ticks()
    if tick > 120 && byt.wheel() != 0 {
        byt.sound()
    }
    if tick == 81 && byt.all_buttons() != 0 {
        input_probe = true
        byt.sound()
    }
    if input_probe && tick >= 81 && tick <= 88 {
        assert(byt.capabilities().input_version == 2)
        assert(byt.buttons() == 0)
        hover, hx, hy := byt.pointer_position()
        active, legacy_x, legacy_y := byt.pointer()
        if tick == 81 || tick == 82 {
            assert(byt.all_buttons() == 0xffff0000)
            assert(hover && hx == 80.5 && hy == 60.75)
            assert(!active && legacy_x == 0 && legacy_y == 0)
            keys := []byt.Button {
                .PointerLeft,
                .PointerRight,
                .PointerHover,
                .WheelUp,
                .WheelDown,
                .Inventory,
                .Character,
                .Skills,
                .Quest,
                .Map,
                .Potion1,
                .Potion2,
                .Potion3,
                .Potion4,
                .Shift,
                .Escape,
            }
            for key in keys {
                assert(byt.button(key))
                assert(byt.pressed(key) == (tick == 81))
                assert(!byt.released(key))
            }
            assert(byt.wheel() == 0)
        } else if tick == 83 {
            assert(byt.released(.Escape) && byt.released(.PointerRight))
            assert(!hover && hx == 0 && hy == 0)
        } else if tick == 84 {
            assert(!hover && hx == 0 && hy == 0)
        } else if tick == 85 {
            assert(byt.wheel() == 1)
        } else if tick == 86 {
            assert(byt.wheel() == -1)
        } else if tick == 87 {
            assert(active && legacy_x == 17.25 && legacy_y == 18.5)
            assert(hover && hx == 17.25 && hy == 18.5)
        } else {
            assert(!active && !hover && byt.wheel() == 0)
            assert(byt.released(.PointerLeft))
        }
    }
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

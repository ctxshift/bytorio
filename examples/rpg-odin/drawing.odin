package main

import g "sdk:console"

text :: proc(value: string, x, y: int, color: u32) {
    g.text(value, x, y, color)
}
sprite :: proc(id, x, y: int, scale := 1) {

    g.sprite(id, x, y, scale)
}
actor :: proc(id, x, y, cx, cy: int) {
    sx, sy := x * 16 - cx, 24 + y * 16 - cy
    if sx >= 0 && sx < 384 && sy >= 24 && sy < 184 {

        sprite(id, sx, sy)
    }
}
number :: proc(n: int) -> string {
    values := [21]string {
        "0",
        "1",
        "2",
        "3",
        "4",
        "5",
        "6",
        "7",
        "8",
        "9",
        "10",
        "11",
        "12",
        "13",
        "14",
        "15",
        "16",
        "17",
        "18",
        "19",
        "20",
    }
    return values[clamp(n, 0, 20)]
}

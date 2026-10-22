package main

import byt "sdk:bytorio"
import text "sdk:text"

staging: [text.MAX_BYTES]u8
last_flags: u32

open :: proc(id: u32, value: string) {
    assert(text.configure({
            id              = id,
            value           = value,
            max_bytes       = 12,
            x               = 30,
            y               = 30,
            width           = 200,
            height          = 32,
            selection_start = u32(len(value)),
            selection_end   = u32(len(value)),
        }))
    last_flags = 0
}

init :: proc() { open(1, "Aé") }

update :: proc(_dt: f64) {
    if byt.pressed(.Action) { text.close() }
    if byt.pressed(.Left) { open(2, "") }
    event, ok := text.read(staging[:])
    if ok {
        if event.id == 1 && !event.changed && last_flags == 0 { assert(event.value == "Aé") }
        byt.sound()
        if event.changed { last_flags |= 2; byt.sound() }
        if event.submitted { last_flags |= 4 }
        if event.cancelled { last_flags |= 8 }
        byt.debug_position(f64(len(event.value)), f64(last_flags))
        _, repeated := text.read(staging[:])
        assert(!repeated)
    } else { byt.debug_position(-1, f64(last_flags)) }
}

draw :: proc() {
    byt.clear(byt.rgb(16, 32, 48))
}

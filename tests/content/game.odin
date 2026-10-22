package main

import byt "sdk:bytorio"
import content "sdk:content"

foreign import host "env"
foreign host {
    @(link_name = "content_read")
    raw_read :: proc "c" (id, offset: u32, pointer: rawptr, length: u32) -> u32 ---
}

init :: proc() {
    assert(content.size(0) == 0)
    assert(content.size(9) == 0)
    assert(content.size(7) == 3 * 1024 * 1024)
    assert(content.size(0xffffffff) == 4)
    if content.size(8) != 0 {
        assert(content.size(8) == 65 * 1024 * 1024)
        high: [4]u8
        assert(content.read(8, 64 * 1024 * 1024 + 1023, high[:]))
        assert(high == [4]u8{255, 0, 1, 2})
        assert(content.read(8, content.size(8) - 4, high[:]))
        assert(high == [4]u8{252, 253, 254, 255})
    }
    bytes := [4]u8{91, 91, 91, 91}
    assert(content.read(7, 1023, bytes[:]))
    assert(bytes == [4]u8{255, 0, 1, 2})
    assert(!content.read(7, content.size(7) - 3, bytes[:]))
    assert(bytes == [4]u8{255, 0, 1, 2})
    assert(!content.read(7, 0xffffffff, bytes[:]))
    assert(!content.read(9, 0, bytes[:]))
    assert(content.read(7, content.size(7), bytes[:0]))
    assert(raw_read(7, 0, rawptr(uintptr(0xffffffff)), 4) == 0)
    assert(raw_read(7, 0, nil, 1048577) == 0)
    assert(content.read(0xffffffff, 0, bytes[:]))
    assert(bytes == [4]u8{17, 23, 41, 89})
    byt.debug_position(17, 89)
}

update :: proc(_dt: f64) {
    bytes: [4]u8
    assert(content.read(0xffffffff, 0, bytes[:]))
    assert(bytes[2] == 41)
}

draw :: proc() {
    byt.clear(byt.rgb(17, 23, 41))
}

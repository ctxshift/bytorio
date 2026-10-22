package main

import byt "sdk:bytorio"
import save "sdk:save"

staging: [save.MAX_BYTES]u8

verify_saved :: proc() {
    length := save.read(staging[:])
    assert(length == save.size())
    assert(length == save.MAX_BYTES || length == 4096 || length == 3)
    for i in 0 ..< int(length) {
        expected := u8((i * 37 + 11) % 256) if length != 3 else u8(i + 7)
        assert(staging[i] == expected)
    }
    byt.sound()
}

init :: proc() {
    if save.size() > 0 { verify_saved() }
}

update :: proc(_dt: f64) {
    if byt.pressed(.Action) {
        for i in 0 ..< len(staging) { staging[i] = u8((i * 37 + 11) % 256) }
        result := save.write(staging[:])
        assert(result == .Ready || result == .Pending)
        assert(save.write(staging[:]) == .Error)
        for &byte in staging { byte = 0 }
    }
    if byt.pressed(.Right) { verify_saved() }
    if byt.pressed(.Left) {
        too_large: [save.MAX_BYTES + 1]u8
        assert(save.write(too_large[:]) == .Error)
        assert(save.write(staging[:0]) == .Error)
        small := [1]u8{123}
        assert(save.read(small[:]) == 0 && small[0] == 123)
        byt.sound()
    }
    if byt.pressed(.Up) {
        staging[0], staging[1], staging[2] = 7, 8, 9
        result := save.write(staging[:3])
        assert(result == .Ready || result == .Pending)
        staging[0], staging[1], staging[2] = 0, 0, 0
    }
    if byt.pressed(.Down) {
        for i in 0 ..< 4096 { staging[i] = u8((i * 37 + 11) % 256) }
        result := save.write(staging[:4096])
        assert(result == .Ready || result == .Pending)
        for &byte in staging { byte = 0 }
    }
    // Sixteen-byte units keep the maximum length within debug-position bounds.
    byt.debug_position(f64(save.size()) / 16, f64(save.status()))
}

draw :: proc() { byt.clear(byt.rgb(16, 32, 48)) }

package console_core

import "core:math"
import abi "../abi"

SAMPLE_RATE :: 48000
SAMPLE_COUNT :: SAMPLE_RATE / 3
pixels: [abi.WIDTH * abi.HEIGHT]u32
sample: [SAMPLE_COUNT]f32

sprite_rows: [16]string = {
    "................", ".....######.....", "...##########...", "..############..",
    "..##..####..##..", ".###..####..###.", ".##############.", ".##############.",
    ".####......####.", "..####....####..", "..############..", "...##########...",
    "....########....", "...###....###...", "..###......###..", "................",
}

init :: proc() {
    for i in 0..<SAMPLE_COUNT {
        t := f64(i) / SAMPLE_RATE
        envelope := min(1.0, t * 100) * (1.0 - f64(i) / SAMPLE_COUNT)
        sample[i] = f32(0.22 * envelope * math.sin(6.283185307179586 * (660 * t + 440 * t * t)))
    }
}

valid :: proc(frame: abi.Frame) -> bool {
    return frame.version == abi.VERSION && frame.sprite_x >= -4096 && frame.sprite_x <= 4096 &&
        frame.sprite_y >= -4096 && frame.sprite_y <= 4096 &&
        frame.x >= -4096 && frame.x <= 4096 && frame.y >= -4096 && frame.y <= 4096
}

render :: proc(frame: abi.Frame) -> bool {
    if !valid(frame) { return false }
    for &pixel in pixels { pixel = frame.clear }
    for row in 0..<16 {
        for col in 0..<16 {
            x, y := int(frame.sprite_x) + col, int(frame.sprite_y) + row
            if sprite_rows[row][col] == '#' && x >= 0 && x < abi.WIDTH && y >= 0 && y < abi.HEIGHT {
                pixels[y * abi.WIDTH + x] = 0xffc0f070
            }
        }
    }
    return true
}

hash :: proc() -> u32 {
    result := u32(2166136261)
    for pixel in pixels {
        for shift in 0..<4 { result = (result ~ ((pixel >> u32(shift * 8)) & 255)) * 16777619 }
    }
    return result
}

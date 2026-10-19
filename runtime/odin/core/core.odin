package console_core

import abi "../abi"
import "core:math"

SAMPLE_RATE :: 48000
SAMPLE_COUNT :: SAMPLE_RATE / 3
pixels: [abi.WIDTH * abi.HEIGHT]u32
width, height: int = abi.WIDTH, abi.HEIGHT
sample: [SAMPLE_COUNT]f32
sprite_count: int
atlas: [256][256]u32
font: [128][7]u8

sprite_rows: [16]string = {
    "................",
    ".....######.....",
    "...##########...",
    "..############..",
    "..##..####..##..",
    ".###..####..###.",
    ".##############.",
    ".##############.",
    ".####......####.",
    "..####....####..",
    "..############..",
    "...##########...",
    "....########....",
    "...###....###...",
    "..###......###..",
    "................",
}

set_display :: proc(mode: u32) -> bool {
    if !abi.valid_display(mode) {

        return false
    }
    width, height = int(mode >> 16), int(mode & 65535)
    return true
}

init :: proc() {
    width, height = abi.WIDTH, abi.HEIGHT
    sprite_count = 0
    font = {}
    for i in 0 ..< SAMPLE_COUNT {
        t := f64(i) / SAMPLE_RATE
        envelope := min(1.0, t * 100) * (1.0 - f64(i) / SAMPLE_COUNT)
        sample[i] = f32(0.22 * envelope * math.sin(6.283185307179586 * (660 * t + 440 * t * t)))
    }
}

valid :: proc(frame: abi.Frame) -> bool {
    return(
        frame.version == abi.VERSION &&
        frame.clear >> 24 == 255 &&
        frame.sprite_x >= -4096 &&
        frame.sprite_x <= 4096 &&
        frame.sprite_y >= -4096 &&
        frame.sprite_y <= 4096 &&
        frame.x >= -4096 &&
        frame.x <= 4096 &&
        frame.y >= -4096 &&
        frame.y <= 4096 \
    )
}

render :: proc(frame: abi.Frame) -> bool {
    if !valid(frame) {

        return false
    }
    for &pixel in pixels[:width * height] {

        pixel = frame.clear
    }
    for row in 0 ..< 16 {
        for col in 0 ..< 16 {
            x, y := int(frame.sprite_x) + col, int(frame.sprite_y) + row
            if sprite_rows[row][col] == '#' && x >= 0 && x < width && y >= 0 && y < height {
                pixels[y * width + x] = 0xffc0f070
            }
        }
    }
    return true
}

hash :: proc() -> u32 {
    result := u32(2166136261)
    for pixel in pixels[:width * height] {
        for shift in 0 ..< 4 {

            result = (result ~ ((pixel >> u32(shift * 8)) & 255)) * 16777619
        }
    }
    return result
}

render_commands :: proc(commands: []abi.Command) -> bool {
    if len(commands) > abi.MAX_COMMANDS {

        return false
    }
    for c in commands {
        if c.color >> 24 != 255 ||
           c.x < -4096 ||
           c.x > 4096 ||
           c.y < -4096 ||
           c.y > 4096 ||
           c.w < 0 ||
           c.w > 4096 ||
           c.h < 0 ||
           c.h > 4096 {

            return false
        }
        for y := max(0, int(c.y)); y < min(height, int(c.y + c.h)); y += 1 {
            for x := max(0, int(c.x)); x < min(width, int(c.x + c.w)); x += 1 {

                pixels[y * width + x] = c.color
            }
        }
    }
    return true
}

u32_le :: proc(bytes: []u8, offset: int) -> u32 {
    return(
        u32(bytes[offset]) |
        u32(bytes[offset + 1]) << 8 |
        u32(bytes[offset + 2]) << 16 |
        u32(bytes[offset + 3]) << 24 \
    )
}
load_graphics :: proc(bytes: []u8) -> bool {
    sprite_count = 0
    if len(bytes) < 80 ||
       len(bytes) > abi.MAX_GRAPHICS_BYTES ||
       u32_le(bytes, 0) != 0x31584647 ||
       u32_le(bytes, 8) != 16 ||
       u32_le(bytes, 12) != 128 {

        return false
    }
    count := int(u32_le(bytes, 4))
    if count < 1 || count > 256 || len(bytes) != 80 + count * 256 + 128 * 7 {

        return false
    }
    palette: [16]u32
    for &color, i in palette {
        color = u32_le(bytes, 16 + i * 4)
        if color >> 24 != 255 {

            return false
        }
    }
    for id in 0 ..< count {
        for px in 0 ..< 256 {
            index := bytes[80 + id * 256 + px]
            if index != 255 && index >= 16 {

                return false
            }
            atlas[id][px] = 0 if index == 255 else palette[index]
        }
    }
    for c in 0 ..< 128 {
        for y in 0 ..< 7 {
            row := bytes[80 + count * 256 + c * 7 + y]
            if row > 31 {

                return false
            }
            font[c][y] = row
        }
    }
    sprite_count = count
    return true
}
fill_rect :: proc(x, y, w, h: int, color: u32) {
    for py := max(0, y); py < min(height, y + h); py += 1 {
        for px := max(0, x); px < min(width, x + w); px += 1 {

            pixels[py * width + px] = color
        }
    }
}
render_batch :: proc(commands: []abi.Draw_Command, text: []u8) -> bool {
    if len(commands) > abi.MAX_COMMANDS || len(text) > abi.MAX_TEXT_BYTES {

        return false
    }
    for c in commands {
        if c.x < -4096 || c.x > 4096 || c.y < -4096 || c.y > 4096 {

            return false
        }
        x, y := int(c.x), int(c.y)
        switch c.kind {
        case 0:
            if c.color >> 24 != 255 {

                return false
            }
            if c.w < 0 || c.w > 4096 || c.h < 0 || c.h > 4096 {

                return false
            }
            fill_rect(x, y, int(c.w), int(c.h), c.color)
        case 1:
            if c.w < 0 || int(c.w) >= sprite_count || c.h < 1 || c.h > 8 {

                return false
            }
            scale := int(c.h)
            for row in 0 ..< 16 {
                if scale == 1 && (y + row < 0 || y + row >= height) {

                    continue
                }
                for col in 0 ..< 16 {
                    color := atlas[c.w][row * 16 + col]
                    if color == 0 {

                        continue
                    }
                    if scale == 1 {
                        if x + col >= 0 && x + col < width {

                            pixels[(y + row) * width + x + col] = color
                        }
                    } else {

                        fill_rect(x + col * scale, y + row * scale, scale, scale, color)
                    }
                }
            }
        case 3:
            if c.color >= u32(sprite_count) || c.w < 1 || c.w > 128 || c.h < 1 || c.h > 128 {

                return false
            }
            for py := max(0, y); py < min(height, y + int(c.h)); py += 1 {
                for px := max(0, x); px < min(width, x + int(c.w)); px += 1 {
                    color :=
                        atlas[c.color][(py - y) * 16 / int(c.h) * 16 + (px - x) * 16 / int(c.w)]
                    if color != 0 {

                        pixels[py * width + px] = color
                    }
                }
            }
        case 2:
            if c.color >> 24 != 255 {

                return false
            }
            if sprite_count == 0 ||
               c.offset > u32(len(text)) ||
               c.length > u32(len(text)) - c.offset ||
               c.length > 1024 {

                return false
            }
            px, py := x, y
            for char in text[c.offset:c.offset + c.length] {
                if char == '\n' {

                    px = x
                    py += 9
                    continue
                }
                if char >= 128 {

                    return false
                }
                for row in 0 ..< 7 {
                    for col in 0 ..< 5 {
                        if font[char][row] & u8(1 << u32(4 - col)) != 0 &&
                           px + col >= 0 &&
                           px + col < width &&
                           py + row >= 0 &&
                           py + row < height {

                            pixels[(py + row) * width + px + col] = c.color
                        }
                    }
                }
                px += 6
            }
        case:
            return false
        }
    }
    return true
}

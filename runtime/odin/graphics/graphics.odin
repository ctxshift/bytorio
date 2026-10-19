package graphics

import abi "../abi"

// Sprites and text remain high-level commands until the shared renderer.
Command :: abi.Draw_Command
MAX_COMMANDS :: abi.MAX_COMMANDS
commands: [MAX_COMMANDS]Command
count: u32
overflow: bool
text_bytes: [abi.MAX_TEXT_BYTES]u8
text_count: u32
display_mode: u32 = abi.DISPLAY_HIGH
set_display :: proc(mode: u32) -> bool {
    if !abi.valid_display(mode) {

        return false
    }
    display_mode = mode
    return true
}

begin :: proc() {

    count = 0
    text_count = 0
    overflow = false
}
rect :: proc(x, y, w, h: int, color: u32) {
    if w <= 0 ||
       h <= 0 ||
       x >= int(display_mode >> abi.DISPLAY_DIMENSION_BITS) ||
       y >= int(display_mode & abi.DISPLAY_DIMENSION_MASK) ||
       x + w <= 0 ||
       y + h <= 0 {

        return
    }
    if count == MAX_COMMANDS {

        overflow = true
        return
    }
    commands[count] = Command {
        kind  = 0,
        x     = i32(x),
        y     = i32(y),
        w     = i32(w),
        h     = i32(h),
        color = color,
    }
    count += 1
}
sprite :: proc(id, x, y: int, scale := 1) {
    if count == MAX_COMMANDS {

        overflow = true
        return
    }
    commands[count] = Command {
        kind = 1,
        x    = i32(x),
        y    = i32(y),
        w    = i32(id),
        h    = i32(scale),
    }
    count += 1
}
sprite_size :: proc(id, x, y, w, h: int) {
    if count == MAX_COMMANDS {

        overflow = true
        return
    }
    commands[count] = Command {
        kind  = 3,
        x     = i32(x),
        y     = i32(y),
        w     = i32(w),
        h     = i32(h),
        color = u32(id),
    }
    count += 1
}
text :: proc(value: string, x, y: int, color: u32) {
    if count == MAX_COMMANDS || len(value) > abi.MAX_TEXT_BYTES - int(text_count) {

        overflow = true
        return
    }
    for byte, i in transmute([]u8)value {

        text_bytes[int(text_count) + i] = byte
    }
    commands[count] = Command {
        kind   = 2,
        x      = i32(x),
        y      = i32(y),
        color  = color,
        offset = text_count,
        length = u32(len(value)),
    }
    text_count += u32(len(value))
    count += 1
}
image :: proc(rows: []string, palette: []u32, x, y: int, scale := 1) {
    for row, ry in rows {
        col := 0
        for col < len(row) {
            ink := row[col]
            end := col + 1
            for end < len(row) && row[end] == ink {

                end += 1
            }
            if ink != '.' {
                index := int(ink - '0')
                if ink >= 'a' {

                    index = int(ink - 'a') + 10
                }
                if index >= 0 && index < len(palette) {

                    rect(
                        x + col * scale,
                        y + ry * scale,
                        (end - col) * scale,
                        scale,
                        palette[index],
                    )
                }
            }
            col = end
        }
    }
}

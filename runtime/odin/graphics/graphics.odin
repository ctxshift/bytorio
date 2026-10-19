package graphics

import abi "../abi"

// The guest SDK builds a bounded display list; the player only draws rectangles.
Command :: abi.Command
MAX_COMMANDS :: abi.MAX_COMMANDS
commands: [MAX_COMMANDS]Command
count: u32
overflow: bool

begin :: proc() { count = 0; overflow = false }
rect :: proc(x, y, w, h: int, color: u32) {
    if w <= 0 || h <= 0 || x >= abi.WIDTH || y >= abi.HEIGHT || x+w <= 0 || y+h <= 0 { return }
    if count == MAX_COMMANDS { overflow = true; return }
    commands[count] = Command{i32(x), i32(y), i32(w), i32(h), color}
    count += 1
}
image :: proc(rows: []string, palette: []u32, x, y: int, scale := 1) {
    for row, ry in rows {
        col := 0
        for col < len(row) {
            ink := row[col]
            end := col+1
            for end < len(row) && row[end] == ink { end += 1 }
            if ink != '.' {
                index := int(ink-'0')
                if ink >= 'a' { index = int(ink-'a')+10 }
                if index >= 0 && index < len(palette) { rect(x+col*scale, y+ry*scale, (end-col)*scale, scale, palette[index]) }
            }
            col = end
        }
    }
}

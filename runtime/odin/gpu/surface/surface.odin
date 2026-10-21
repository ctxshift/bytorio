package surface

import resources "../../resources"
import "core:math"

RECORD_FLOATS :: 12
POINTS_PER_PATCH :: 4
CACHE_BYTES :: 64 * 1024 * 1024
MAX_PATCHES :: CACHE_BYTES / (RECORD_FLOATS * size_of(f32))

Rectangle :: struct {
    low:           [3]f32,
    axes:          [2]int,
    width, height: int,
    color:         u32,
    reverse:       bool,
}

// Host quality experiment, not a new cartridge resource or protocol. Validate
// the complete rectangle field before allocating a bounded resident patch array.
patches :: proc(data: []u8, vertex_count, index_count: u32, palette: []u8 = nil) -> ([]f32, bool) {
    if index_count % 6 != 0 ||
       u64(vertex_count) * 16 + u64(index_count) * 4 > u64(len(data)) { return nil, false }
    rectangles := make([]Rectangle, int(index_count) / 6)
    defer delete(rectangles)
    count := 0
    indices := data[int(vertex_count) * 16:]
    for &rectangle, face in rectangles {
        points: [6][3]f32
        colors: [6]u32
        for &point, i in points {
            index := resources.u32le(indices, (face * 6 + i) * 4)
            if index >= vertex_count { return nil, false }
            at := int(index) * 16
            for &v, axis in point { v = f32(resources.f32le(data, at + axis * 4)) }
            colors[i] = resources.u32le(data, at + 12)
            if len(palette) != 0 {
                if u64(colors[i]) * 4 + 4 > u64(len(palette)) { return nil, false }
                colors[i] = resources.u32le(palette, int(colors[i]) * 4)
            }
        }
        normals: [2][3]f32
        for &normal, triangle in normals {
            a, b: [3]f32
            for i in 0 ..< 3 {
                a[i] = points[triangle * 3 + 1][i] - points[triangle * 3][i]
                b[i] = points[triangle * 3 + 2][i] - points[triangle * 3][i]
            }
            normal = {
                a[1] * b[2] - a[2] * b[1],
                a[2] * b[0] - a[0] * b[2],
                a[0] * b[1] - a[1] * b[0],
            }
        }
        axis := -1
        for value, i in normals[0] {
            if math.is_nan(value) ||
               math.is_inf(value) ||
               value != normals[1][i] { return nil, false }
            if value != 0 {
                if axis != -1 { return nil, false }
                axis = i
            }
        }
        if axis == -1 { return nil, false }
        next := 0
        for i in 0 ..< 3 {
            if i != axis { rectangle.axes[next] = i; next += 1 }
        }
        rectangle.low = points[0]
        high := points[0]
        for point, i in points {
            if colors[i] != colors[0] { return nil, false }
            for value, j in point {
                rectangle.low[j] = min(rectangle.low[j], value)
                high[j] = max(high[j], value)
            }
        }
        width := high[rectangle.axes[0]] - rectangle.low[rectangle.axes[0]]
        height := high[rectangle.axes[1]] - rectangle.low[rectangle.axes[1]]
        if rectangle.low[axis] != high[axis] ||
           width <= 0 ||
           height <= 0 ||
           width > MAX_PATCHES ||
           height > MAX_PATCHES ||
           math.floor(width) != width ||
           math.floor(height) != height ||
           abs(normals[0][axis]) != width * height { return nil, false }
        corners: [2]u32
        for point, i in points {
            corner := u32(0)
            for value, j in point {
                if value != rectangle.low[j] && value != high[j] { return nil, false }
            }
            if point[rectangle.axes[0]] == high[rectangle.axes[0]] { corner |= 1 }
            if point[rectangle.axes[1]] == high[rectangle.axes[1]] { corner |= 2 }
            corners[i / 3] |= 1 << corner
        }
        diagonal := corners[0] & corners[1]
        if corners[0] | corners[1] != 15 || (diagonal != 6 && diagonal != 9) { return nil, false }
        if f64(width) * f64(height) > f64(MAX_PATCHES - count) { return nil, false }
        rectangle.width, rectangle.height = int(width), int(height)
        rectangle.color = colors[0]
        rectangle.reverse = (normals[0][axis] < 0) != (axis == 1)
        count += rectangle.width * rectangle.height
    }
    records := make([]f32, count * RECORD_FLOATS)
    cursor := 0
    for rectangle in rectangles {
        for y in 0 ..< rectangle.height {
            for x in 0 ..< rectangle.width {
                point := rectangle.low
                point[rectangle.axes[0]] += f32(x)
                point[rectangle.axes[1]] += f32(y)
                for value, i in point { records[cursor + i] = value }
                for i in 0 ..< 3 { records[cursor + 3 + i] = f32((rectangle.color >> u32(i * 8)) & 255) / 255 }
                a := rectangle.axes[1] if rectangle.reverse else rectangle.axes[0]
                b := rectangle.axes[0] if rectangle.reverse else rectangle.axes[1]
                records[cursor + 6 + a] = 1
                records[cursor + 9 + b] = 1
                cursor += RECORD_FLOATS
            }
        }
    }
    return records, true
}

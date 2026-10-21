package mesh_test

import surface "../../runtime/odin/gpu/surface"
import r "../../runtime/odin/resources"
import "core:testing"

surface_rectangle :: proc(width: f64 = 2) -> []u8 {
    bytes := make([]u8, 4 * 16 + 6 * 4)
    corners := [4][3]f64{{-2, -1, 3}, {width - 2, -1, 3}, {width - 2, 0, 3}, {-2, 0, 3}}
    for point, i in corners {
        for value, axis in point { r.putf(bytes, i * 16 + axis * 4, value) }
        r.put32(bytes, i * 16 + 12, 0xff0000ff)
    }
    for index, i in ([6]u32{0, 1, 2, 0, 2, 3}) { r.put32(bytes, 64 + i * 4, index) }
    return bytes
}

@(test)
surface_records_and_bounds :: proc(test: ^testing.T) {
    bytes := surface_rectangle()
    defer delete(bytes)
    records, ok := surface.patches(bytes, 4, 6)
    defer delete(records)
    testing.expect(test, ok)
    expected := [24]f32{-2, -1, 3, 1, 0, 0, 1, 0, 0, 0, 1, 0, -1, -1, 3, 1, 0, 0, 1, 0, 0, 0, 1, 0}
    testing.expect_value(test, len(records), len(expected))
    for value, i in expected { testing.expect_value(test, records[i], value) }
    r.putf(bytes, 0, 100)
    testing.expect_value(test, records[0], f32(-2))

    huge := surface_rectangle(2000000)
    defer delete(huge)
    rejected, valid := surface.patches(huge, 4, 6)
    defer delete(rejected)
    testing.expect(test, !valid && len(rejected) == 0)
    triangle, triangle_ok := surface.patches(bytes, 4, 3)
    defer delete(triangle)
    testing.expect(test, !triangle_ok)
}

@(test)
surface_rejects_nonflat_or_gradient_faces :: proc(test: ^testing.T) {
    bytes := surface_rectangle()
    defer delete(bytes)
    r.putf(bytes, 2 * 16 + 8, 4)
    bent, ok := surface.patches(bytes, 4, 6)
    defer delete(bent)
    testing.expect(test, !ok)
    r.putf(bytes, 2 * 16 + 8, 3)
    r.put32(bytes, 12, 0xff00ff00)
    gradient, gradient_ok := surface.patches(bytes, 4, 6)
    defer delete(gradient)
    testing.expect(test, !gradient_ok)
}

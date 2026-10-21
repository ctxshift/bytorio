package gfx3d

import w "../../../runtime/odin/resource_protocol"
import gfx "../gfx"
import "core:math"

Billboard_Mode :: enum {
    Facing,
    Upright,
}

Billboard_Desc :: struct {
    position: [3]f64,
    size:     [2]f64,
    pivot:    [2]f64,
    view:     Matrix,
    rotation: f64,
    mode:     Billboard_Mode,
}

billboard :: proc() -> Textured_Mesh {
    vertices := [4]Textured_Vertex {
        {{0, 0, 0}, 0xffffffff, {0, 1}},
        {{1, 0, 0}, 0xffffffff, {1, 1}},
        {{1, 1, 0}, 0xffffffff, {1, 0}},
        {{0, 1, 0}, 0xffffffff, {0, 0}},
    }
    indices := [6]u32{0, 2, 1, 0, 3, 2}
    return textured_mesh(vertices[:], indices[:])
}

billboard_model :: proc(desc: Billboard_Desc) -> Matrix {
    finite :: proc(value: f64) -> bool {
        return !math.is_nan(value) && !math.is_inf(value) && abs(value) <= w.max3dCoordinate
    }
    for value in desc.view { assert(finite(f64(value)), "invalid billboard view") }
    for value in desc.position { assert(finite(value), "invalid billboard position") }
    for value in desc.size { assert(finite(value) && value > 0, "invalid billboard size") }
    for value in desc.pivot { assert(finite(value), "invalid billboard pivot") }
    assert(finite(desc.rotation), "invalid billboard rotation")
    assert(desc.mode == .Facing || desc.mode == .Upright, "invalid billboard mode")
    assert(
        desc.view[3] == 0 && desc.view[7] == 0 && desc.view[11] == 0 && desc.view[15] == 1,
        "billboard requires an affine camera view, without projection",
    )
    right := [3]f64{f64(desc.view[0]), f64(desc.view[4]), f64(desc.view[8])}
    up := [3]f64{f64(desc.view[1]), f64(desc.view[5]), f64(desc.view[9])}
    if desc.mode == .Upright {
        right[1] = 0
        up = {0, 1, 0}
    }
    right = normalize(right)
    alignment := right[0] * up[0] + right[1] * up[1] + right[2] * up[2]
    for &value, axis in up { value -= right[axis] * alignment }
    up = normalize(up)
    c, s := math.sin(desc.rotation + math.PI / 2), math.sin(desc.rotation)
    horizontal, vertical: [3]f64
    for axis in 0 ..< 3 {
        horizontal[axis] = (right[axis] * c + up[axis] * s) * desc.size[0]
        vertical[axis] = (-right[axis] * s + up[axis] * c) * desc.size[1]
    }
    model := IDENTITY
    normal := [3]f64 {
        right[1] * up[2] - right[2] * up[1],
        right[2] * up[0] - right[0] * up[2],
        right[0] * up[1] - right[1] * up[0],
    }
    for axis in 0 ..< 3 {
        model[8 + axis] = f32(normal[axis])
        model[axis], model[4 + axis] = f32(horizontal[axis]), f32(vertical[axis])
        model[12 + axis] = f32(
            desc.position[axis] -
            horizontal[axis] * desc.pivot[0] -
            vertical[axis] * desc.pivot[1],
        )
    }
    return model
}

draw_billboard :: proc(
    pass: gfx.Pass,
    geometry: Textured_Mesh,
    surface: Material,
    desc: Billboard_Desc,
) {
    draw_textured(pass, geometry, surface, billboard_model(desc))
}

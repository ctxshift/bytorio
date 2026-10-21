package gfx3d

import w "../../../runtime/odin/resource_protocol"
import r "../../../runtime/odin/resources"
import gfx "../gfx"
import t "../resource"
import "core:math"

Mesh :: distinct t.Handle
Textured_Mesh :: distinct t.Handle
Material :: distinct t.Handle
Depth :: distinct t.Handle
Camera :: distinct t.Handle
Voxel :: distinct t.Handle
Matrix :: [16]f32
IDENTITY :: Matrix{1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}

Vertex :: struct {
    position: [3]f32,
    color:    u32,
}

Textured_Vertex :: struct {
    position: [3]f32,
    color:    u32,
    uv:       [2]f32,
}

Address_Mode :: enum u32 {
    Clamp  = w.addressClamp,
    Repeat = w.addressRepeat,
}

Material_Options :: struct {
    address_u, address_v: Address_Mode,
}

material :: proc(texture: gfx.Texture, options := Material_Options{}) -> Material {
    return make_material(texture, options, w.op_create_material, 0)
}

cutout_material :: proc(
    texture: gfx.Texture,
    cutoff := u32(w.defaultAlphaCutoff),
    options := Material_Options{},
) -> Material {
    if !t.valid(cutoff <= w.maxAlphaCutoff, "alpha cutoff must be a byte") { return {} }
    return make_material(texture, options, w.op_create_cutout_material, cutoff)
}

make_material :: proc(
    texture: gfx.Texture,
    options: Material_Options,
    opcode, cutoff: u32,
) -> Material {
    if !t.check(t.Handle(texture), u32(r.Kind.Texture)) { return {} }
    if !t.valid(
        t.slots[(texture.id & w.handleIndexMask) - 1].format == w.format_rgba8,
        "material requires an RGBA texture",
    ) { return {} }
    h := t.reserve(w.kindMaterial, 0)
    args := [8]u32{texture.id, u32(options.address_u), u32(options.address_v), cutoff, 0, 0, 0, 0}
    t.emit(opcode, h, args[:])
    return Material(h)
}

textured_mesh :: proc(vertices: []Textured_Vertex, indices: []u32) -> Textured_Mesh {
    if !t.valid(
        len(vertices) > 0 &&
        len(vertices) <= w.maxMeshVertices &&
        len(indices) > 0 &&
        len(indices) <= w.maxMeshIndices &&
        len(indices) % 3 == 0,
        "invalid textured mesh counts",
    ) { return {} }
    bytes := make([]u8, len(vertices) * w.texturedVertexBytes + len(indices) * w.meshIndexBytes)
    defer delete(bytes)
    for vertex, i in vertices {
        at := i * w.texturedVertexBytes
        for p, axis in vertex.position { r.put32(bytes, at + axis * 4, transmute(u32)p) }
        r.put32(bytes, at + w.meshColorOffset, vertex.color)
        for uv, axis in vertex.uv { r.put32(bytes, at + w.texturedUvOffset + axis * 4, transmute(u32)uv) }
    }
    for index, i in indices { r.put32(bytes, len(vertices) * w.texturedVertexBytes + i * w.meshIndexBytes, index) }
    h := t.reserve(w.kindTexturedMesh, 0)
    args := [8]u32{u32(len(vertices)), u32(len(indices)), 0, 0, 0, 0, 0, 0}
    t.emit(w.op_create_textured_mesh, h, args[:], bytes)
    return Textured_Mesh(h)
}

Camera_Desc :: struct {
    view_projection:    Matrix,
    light:              [3]f32,
    ambient:            f32,
    fog_color:          u32,
    fog_start, fog_end: f32,
}

camera_defaults :: proc(view: Matrix) -> Camera_Desc {
    return {
        view_projection = view,
        ambient         = 1,
        fog_color       = 0xff000000,
        fog_start       = 1,
        fog_end         = 2,
    }
}

identity :: proc() -> Matrix {
    return {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}
}

multiply :: proc(a, b: Matrix) -> (m: Matrix) {
    for col in 0 ..< 4 {
        for row in 0 ..< 4 {
            sum := f64(0)
            for i in 0 ..< 4 {
                sum += f64(a[i * 4 + row]) * f64(b[col * 4 + i])
            }

            m[col * 4 + row] = f32(sum)
        }
    }

    return
}

pose :: proc(x, y, z, yaw, scale: f64) -> Matrix {
    c, s := f32(math.sin(yaw + math.PI / 2) * scale), f32(math.sin(yaw) * scale)
    return {c, 0, -s, 0, 0, f32(scale), 0, 0, s, 0, c, 0, f32(x), f32(y), f32(z), 1}
}

orthographic :: proc(left, right, bottom, top, near, far: f64) -> Matrix {
    assert(right > left && top > bottom && far > near)
    return {
        f32(2 / (right - left)),
        0,
        0,
        0,
        0,
        f32(2 / (top - bottom)),
        0,
        0,
        0,
        0,
        f32(1 / (far - near)),
        0,
        f32(-(right + left) / (right - left)),
        f32(-(top + bottom) / (top - bottom)),
        f32(-near / (far - near)),
        1,
    }
}

perspective :: proc(fovy, aspect, near, far: f64) -> Matrix {
    assert(fovy > 0 && fovy < math.PI && aspect > 0 && near > 0 && far > near)
    s := math.sin(fovy / 2 + math.PI / 2) / math.sin(fovy / 2)
    return {
        f32(s / aspect),
        0,
        0,
        0,
        0,
        f32(s),
        0,
        0,
        0,
        0,
        f32(far / (far - near)),
        1,
        0,
        0,
        f32(-near * far / (far - near)),
        0,
    }
}

normalize :: proc(v: [3]f64) -> [3]f64 {
    length := math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
    assert(length > 0)
    return {v[0] / length, v[1] / length, v[2] / length}
}

look_at :: proc(eye, target: [3]f64) -> Matrix {
    z := normalize({target[0] - eye[0], target[1] - eye[1], target[2] - eye[2]})
    x := normalize({z[2], 0, -z[0]})
    y := [3]f64{z[1] * x[2] - z[2] * x[1], z[2] * x[0] - z[0] * x[2], z[0] * x[1] - z[1] * x[0]}

    dot :: proc(a, b: [3]f64) -> f64 {
        return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
    }

    return {
        f32(x[0]),
        f32(y[0]),
        f32(z[0]),
        0,
        f32(x[1]),
        f32(y[1]),
        f32(z[1]),
        0,
        f32(x[2]),
        f32(y[2]),
        f32(z[2]),
        0,
        f32(-dot(x, eye)),
        f32(-dot(y, eye)),
        f32(-dot(z, eye)),
        1,
    }
}

matrix_bytes :: proc(m: Matrix, bytes: []u8) {
    for value, i in m {
        r.put32(bytes, i * 4, transmute(u32)value)
    }
}

mesh :: proc(vertices: []Vertex, indices: []u32) -> Mesh {
    if !t.valid(
        len(vertices) > 0 &&
        len(vertices) <= w.maxMeshVertices &&
        len(indices) > 0 &&
        len(indices) <= w.maxMeshIndices &&
        len(indices) % 3 == 0,
        "invalid mesh counts",
    ) {
        return {}
    }

    bytes := make([]u8, len(vertices) * w.meshVertexBytes + len(indices) * w.meshIndexBytes)
    defer delete(bytes)
    for v, i in vertices {
        for p, j in v.position {
            r.put32(bytes, i * w.meshVertexBytes + j * 4, transmute(u32)p)
        }

        r.put32(bytes, i * w.meshVertexBytes + w.meshColorOffset, v.color)
    }

    for index, i in indices {
        r.put32(bytes, len(vertices) * w.meshVertexBytes + i * 4, index)
    }

    h := t.reserve(w.kindMesh, 0)
    args := [8]u32{u32(len(vertices)), u32(len(indices)), 0, 0, 0, 0, 0, 0}

    t.emit(w.op_create_mesh, h, args[:], bytes)
    return Mesh(h)
}

depth :: proc(width, height: u32) -> Depth {
    h := t.reserve(w.kindDepth, 0)
    args := [8]u32{width, height, 0, 0, 0, 0, 0, 0}

    t.emit(w.op_create_depth, h, args[:])
    return Depth(h)
}

camera :: proc(desc: Camera_Desc) -> Camera {
    bytes: [w.cameraBytes]u8
    matrix_bytes(desc.view_projection, bytes[:w.modelBytes])
    for value, i in desc.light {
        r.put32(bytes[:], w.cameraLightOffset + i * 4, transmute(u32)value)
    }

    r.put32(bytes[:], w.cameraAmbientOffset, transmute(u32)desc.ambient)
    r.put32(bytes[:], w.cameraFogColorOffset, desc.fog_color)
    r.put32(bytes[:], w.cameraFogStartOffset, transmute(u32)desc.fog_start)
    r.put32(bytes[:], w.cameraFogEndOffset, transmute(u32)desc.fog_end)
    h := t.reserve(w.kindCamera, 0)
    args: [8]u32
    t.emit(w.op_create_camera, h, args[:], bytes[:])
    return Camera(h)
}

voxel :: proc(width, height, depth: u32, palette: gfx.Palette, cells: []u8) -> Voxel {
    if !t.check(t.Handle(palette), 4) {
        return {}
    }

    h := t.reserve(w.kindVoxel, 0)
    args := [8]u32{width, height, depth, palette.id, 0, 0, 0, 0}

    t.emit(w.op_create_voxel, h, args[:], cells)
    return Voxel(h)
}

edit :: proc(volume: Voxel, x, y, z, width, height, depth: u32, cells: []u8) {
    if !t.check(t.Handle(volume), w.kindVoxel) {
        return
    }

    args := [8]u32{x, y, z, width, height, depth, 0, 0}

    t.emit(w.op_edit_voxel, t.Handle(volume), args[:], cells)
}

bind :: proc(pass: gfx.Pass, attachment: Depth, view: Camera, clear := true) {
    if !gfx.check_pass(pass) ||
       !t.check(t.Handle(attachment), w.kindDepth) ||
       !t.check(t.Handle(view), w.kindCamera) {
        return
    }

    args := [8]u32{view.id, u32(clear), 0, 0, 0, 0, 0, 0}

    t.emit(w.op_begin_3d, t.Handle(attachment), args[:])
}

draw :: proc(pass: gfx.Pass, geometry: $Geometry, model := IDENTITY) {
    #assert(Geometry == Mesh || Geometry == Voxel)
    if !gfx.check_pass(pass) ||
       !t.check(t.Handle(geometry), w.kindMesh if Geometry == Mesh else w.kindVoxel) {
        return
    }

    bytes: [w.modelBytes]u8
    matrix_bytes(model, bytes[:])
    args: [8]u32
    t.emit(w.op_draw_mesh, t.Handle(geometry), args[:], bytes[:])
}

draw_textured :: proc(
    pass: gfx.Pass,
    geometry: Textured_Mesh,
    surface: Material,
    model := IDENTITY,
) {
    if !gfx.check_pass(pass) ||
       !t.check(t.Handle(geometry), w.kindTexturedMesh) ||
       !t.check(t.Handle(surface), w.kindMaterial) { return }
    bytes: [w.modelBytes]u8
    matrix_bytes(model, bytes[:])
    args := [8]u32{surface.id, 0, 0, 0, 0, 0, 0, 0}
    t.emit(w.op_draw_textured_mesh, t.Handle(geometry), args[:], bytes[:])
}

destroy :: proc(value: $Resource) {
    #assert(
        Resource == Mesh ||
        Resource == Textured_Mesh ||
        Resource == Material ||
        Resource == Depth ||
        Resource == Camera ||
        Resource == Voxel,
    )
    h := t.Handle(value)
    if !t.check(h, 0) || !t.valid(t.phase != 2, "3D destruction requires init/update") {
        return
    }

    t.emit(w.op_destroy_resource, h)
    slot := &t.slots[(h.id & w.handleIndexMask) - 1]
    slot.kind = 0
    slot.generation += 1
}

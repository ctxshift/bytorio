package resources

import w "../resource_protocol"
import "core:math"

// Column-major matrices; left-handed view space and homogeneous depth 0 <= z <= w.
Matrix :: [16]f64
CLIP_CAPACITY :: 16
mesh_storage :: proc "contextless" (r: ^Registry) -> (bytes: [3]u64) {
    for slot in r.slots {
        #partial switch slot.kind {
        case .Voxel:
            bytes[0] += u64(slot.width) * u64(slot.height) * u64(slot.volume_depth)
            bytes[1] += u64(len(slot.data)) - u64(slot.mesh_offset)
        case .Mesh, .Textured_Mesh:
            bytes[1] += u64(len(slot.data))
        case .Depth:
            bytes[2] += u64(len(slot.data))
        }
    }

    return
}

work :: proc(t: ^Transaction, amount: int) -> bool {
    if amount < 0 || amount > w.maxPixelWork - t.work {
        return fail(t.registry, "3D pixel work limit exceeded")
    }

    t.work += amount
    return true
}

Clip_Vertex :: struct {
    p:     [4]f64,
    color: [3]f64,
}

f32le :: #force_inline proc(b: []u8, at: int) -> f64 {
    return f64(transmute(f32)u32le(b, at))
}

putf :: proc(b: []u8, at: int, value: f64) {
    put32(b, at, transmute(u32)f32(value))
}

finite :: proc(v: f64, limit := f64(w.max3dCoordinate)) -> bool {
    return !math.is_nan(v) && !math.is_inf(v) && abs(v) <= limit
}

matrix_read :: proc(b: []u8) -> (m: Matrix, ok: bool) {
    if len(b) != w.modelBytes {
        return
    }

    for &value, i in m {
        value = f32le(b, i * 4)
        if !finite(value) {
            return
        }
    }

    return m, true
}

matrix_point :: proc(m: Matrix, p: [4]f64) -> (q: [4]f64) {
    for row in 0 ..< 4 {
        for col in 0 ..< 4 {
            q[row] += m[col * 4 + row] * p[col]
        }
    }

    return
}

padding_zero :: proc(args: []u32) -> bool {
    for x in args {
        if x != 0 {
            return false
        }
    }

    return true
}

// Copy-on-write works for non-image attachments as well as immutable 3D resources.
mesh_owned :: proc(t: ^Transaction, id: u32, kind: Kind, preserve := true) -> ^Slot {
    slot := lookup(t, id, kind)
    if slot == nil {
        fail(t.registry, "invalid 3D resource handle")
        return nil
    }

    original := &t.registry.slots[(id & w.handleIndexMask) - 1]
    if raw_data(slot.data) == raw_data(original.data) {
        bytes, ok := allocate(t, len(slot.data), zero = false)
        if !ok {
            return nil
        }

        if preserve {
            copy(bytes, slot.data)
            t.copy_bytes += u64(len(bytes))
        }
        slot.data = bytes
    }

    return slot
}

mesh_command :: proc(
    t: ^Transaction,
    op, id: u32,
    descriptor: [8]u32,
    data: []u8,
    phase: u32,
) -> bool {
    a := descriptor
    r := t.registry
    if op == w.op_begin_3d || op == w.op_draw_mesh {
        if phase != 2 || !t.render.active {
            return fail(r, "3D drawing requires an active pass")
        }

        target := image(t, t.render.target)
        if target == nil || target.format != w.format_rgba8 || target.link != 0 {
            return fail(r, "3D requires an RGBA target without stencil")
        }

        if t.render.pipeline != default_pipeline(w.format_rgba8) {
            return fail(r, "3D requires the default opaque pipeline")
        }

        if op == w.op_begin_3d {
            depth := lookup(t, id, .Depth)
            camera := lookup(t, a[0], .Camera)
            if depth == nil ||
               camera == nil ||
               depth.width != target.width ||
               depth.height != target.height ||
               a[1] > 1 ||
               !padding_zero(a[2:]) ||
               len(data) != 0 {
                return fail(r, "invalid 3D depth/camera binding")
            }

            depth = mesh_owned(t, id, .Depth, preserve = a[1] == 0)
            if depth == nil {
                return false
            }

            if a[1] != 0 {
                if !work(t, int(depth.width) * int(depth.height)) {
                    return false
                }

                for at := 0; at < len(depth.data); at += w.depthBytes {
                    putf(depth.data, at, 1)
                }
            }

            t.render.depth, t.render.camera = id, a[0]
            return true
        }

        if t.render.depth == 0 || t.render.camera == 0 || !padding_zero(a[:]) {
            return fail(r, "mesh drawing requires a 3D binding")
        }

        model, ok := matrix_read(data)
        if !ok || model[3] != 0 || model[7] != 0 || model[11] != 0 || model[15] != 1 {
            return fail(r, "invalid affine model matrix")
        }

        slot := lookup(t, id)
        if slot == nil || (slot.kind != .Mesh && slot.kind != .Voxel) {
            return fail(r, "invalid mesh handle")
        }

        return raster_mesh(t, slot, model)
    }

    if phase == 2 {
        return fail(r, "3D resource edits require init/update")
    }

    if op == w.op_edit_voxel {
        return voxel_edit(t, id, a, data)
    }

    slot := unused(t, id)
    if slot == nil {
        return fail(r, "3D creation requires unused handle")
    }

    candidate := Slot {
        generation = slot.generation,
    }

    size := 0
    switch op {
    case w.op_create_mesh, w.op_create_textured_mesh:
        if a[0] == 0 ||
           a[0] > w.maxMeshVertices ||
           a[1] == 0 ||
           a[1] > w.maxMeshIndices ||
           a[1] % 3 != 0 ||
           !padding_zero(a[2:]) {
            return fail(r, "invalid mesh counts")
        }

        textured := op == w.op_create_textured_mesh
        stride := w.texturedVertexBytes if textured else w.meshVertexBytes
        size = int(a[0]) * stride + int(a[1]) * w.meshIndexBytes
        if len(data) != size {
            return fail(r, "invalid mesh byte length")
        }

        for vertex in 0 ..< int(a[0]) {
            at := vertex * stride
            for axis in 0 ..< 3 {
                if !finite(f32le(data, at + axis * 4)) {
                    return fail(r, "invalid mesh position")
                }
            }

            if u32le(data, at + w.meshColorOffset) >> 24 != 255 {
                return fail(r, "mesh colors must be opaque")
            }
            if textured {
                for component in 0 ..< 2 {
                    if !finite(
                        f32le(data, at + w.texturedUvOffset + component * 4),
                        w.maxTextureCoordinate,
                    ) {
                        return fail(r, "invalid mesh UV coordinate")
                    }
                }
            }
        }

        for at := int(a[0]) * stride; at < size; at += w.meshIndexBytes {
            if u32le(data, at) >= a[0] {
                return fail(r, "mesh index outside vertices")
            }
        }

        candidate.kind = .Textured_Mesh if textured else .Mesh
        candidate.vertex_count, candidate.index_count = a[0], a[1]
    case w.op_create_material:
        texture := lookup(t, a[0], .Texture)
        if texture == nil ||
           texture.format != w.format_rgba8 ||
           a[1] > w.addressRepeat ||
           a[2] > w.addressRepeat ||
           !padding_zero(a[3:]) ||
           len(data) != 0 {
            return fail(r, "invalid material texture or sampler")
        }
        candidate.kind, candidate.link = .Material, a[0]
        size = w.descriptorBytes
    case w.op_create_depth:
        if a[0] == 0 ||
           a[0] > w.maxImageAxis ||
           a[1] == 0 ||
           a[1] > w.maxImageAxis ||
           !padding_zero(a[2:]) ||
           len(data) != 0 {
            return fail(r, "invalid depth descriptor")
        }

        count := 0
        for entry in t.slots^ {
            if entry.kind == .Depth {
                count += 1
            }
        }

        if count >= w.maxTargets {
            return fail(r, "depth attachment limit exceeded")
        }

        candidate.kind, candidate.width, candidate.height = .Depth, a[0], a[1]
        size = int(a[0]) * int(a[1]) * w.depthBytes
    case w.op_create_camera:
        if !padding_zero(a[:]) || len(data) != w.cameraBytes {
            return fail(r, "invalid camera bytes")
        }

        _, ok := matrix_read(data[:w.modelBytes])
        if !ok {
            return fail(r, "invalid camera matrix")
        }

        for i in 16 ..< 20 {
            if !finite(f32le(data, i * 4), 1) {
                return fail(r, "invalid lighting")
            }
        }

        if f32le(data, w.cameraAmbientOffset) < 0 ||
           u32le(data, w.cameraFogColorOffset) >> 24 != 255 ||
           !finite(f32le(data, w.cameraFogStartOffset), 2) ||
           !finite(f32le(data, w.cameraFogEndOffset), 2) ||
           f32le(data, w.cameraFogStartOffset) < 0 ||
           f32le(data, w.cameraFogEndOffset) <= f32le(data, w.cameraFogStartOffset) ||
           u32le(data, w.cameraPaddingOffset) != 0 {
            return fail(r, "invalid fog range or camera padding")
        }

        candidate.kind = .Camera
        size = len(data)
    case w.op_create_voxel:
        return voxel_create(t, slot, a, data)
    case:
        return fail(r, "unknown 3D command")
    }

    bytes, ok := allocate(t, size)
    if !ok {
        return false
    }

    if len(data) > 0 {
        copy(bytes, data)
        t.copy_bytes += u64(len(data))
    }

    if candidate.kind == .Depth {
        for at := 0; at < size; at += w.depthBytes {
            putf(bytes, at, 1)
        }
    }

    candidate.data = bytes
    if candidate.kind == .Material {
        for value, i in a { put32(bytes, i * 4, value) }
    }
    if candidate.kind == .Mesh ||
       candidate.kind == .Textured_Mesh { candidate.gpu_version = mesh_version(r) }
    slot^ = candidate
    return true
}

clip_distance :: proc(p: [4]f64, plane: int) -> f64 {
    switch plane {
    case 0:
        return p[0] + p[3]
    case 1:
        return p[3] - p[0]
    case 2:
        return p[1] + p[3]
    case 3:
        return p[3] - p[1]
    case 4:
        return p[2]
    case:
        return p[3] - p[2]
    }
}

clip_lerp :: proc(a, b: Clip_Vertex, t: f64) -> (v: Clip_Vertex) {
    for &x, i in v.p {
        x = a.p[i] + (b.p[i] - a.p[i]) * t
    }

    for &x, i in v.color {
        x = a.color[i] + (b.color[i] - a.color[i]) * t
    }

    return
}

cross3 :: proc(a, b: [3]f64) -> [3]f64 {
    return {a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]}
}

raster_mesh :: proc(t: ^Transaction, mesh: ^Slot, model: Matrix) -> bool {
    camera := lookup(t, t.render.camera, .Camera)
    view, _ := matrix_read(camera.data[:w.modelBytes])
    accelerated := prepare_raster(t)
    t.gpu_ortho = view[3] == 0 && view[7] == 0 && view[11] == 0 && view[15] == 1
    if accelerated && t.registry.pixel_snap && t.gpu_ortho {
        target := image(t, t.render.target)
        old_x, old_y := view[12], view[13]
        view[12] = math.round(view[12] * f64(target.width) / 2) * 2 / f64(target.width)
        view[13] = math.round(view[13] * f64(target.height) / 2) * 2 / f64(target.height)
        t.gpu_residual = {
            (view[12] - old_x) * f64(target.width) / 2,
            (old_y - view[13]) * f64(target.height) / 2,
        }
    }
    triangles := u64(mesh.index_count / 3)
    if t.triangles + triangles > w.maxTrianglesPerCommit {
        return fail(t.registry, "triangle work limit exceeded")
    }

    t.triangles += triangles
    vertices := mesh.data[int(mesh.mesh_offset):][:int(mesh.vertex_count) * w.meshVertexBytes]
    indices := mesh.data[int(mesh.mesh_offset) + len(vertices):]
    if accelerated && t.registry.resident_meshes {
        scratch_size := int(mesh.vertex_count) * size_of(Account_Vertex)
        if scratch_size <= t.budget - t.retained {
            return resident_mesh(t, mesh, model, view, camera)
        }
        // Optional cache accounting must not reject a reference-valid packet.
        if t.resident_count > 0 {
            if !flush_raster(t) { return false }
        } else {
            t.retained -= len(t.gpu_vertices)
            delete(t.gpu_vertices)
            t.gpu_vertices = nil
        }
        accelerated = false
        t.preview_disabled = true
    }
    for at := 0; at < int(mesh.index_count) * w.meshIndexBytes; at += 3 * w.meshIndexBytes {
        input: [3]Clip_Vertex
        world: [3][4]f64
        for &v, i in input {
            pos := int(u32le(indices, at + i * 4)) * w.meshVertexBytes
            world[i] = matrix_point(
                model,
                {f32le(vertices, pos), f32le(vertices, pos + 4), f32le(vertices, pos + 8), 1},
            )
            v.p = matrix_point(view, world[i])
            color := u32le(vertices, pos + w.meshColorOffset)
            if mesh.kind == .Voxel {
                palette := lookup(t, mesh.link, .Palette)
                color = u32le(palette.data, int(color) * 4)
                if color >> 24 != 255 {
                    return fail(t.registry, "occupied voxel palette colors must be opaque")
                }
            }

            for &c, channel in v.color {
                c = f64((color >> u32(channel * 8)) & 255)
            }
        }

        ambient := f32le(camera.data, w.cameraAmbientOffset)
        if ambient != 1 {
            a, b: [3]f64
            for j in 0 ..< 3 {
                a[j] = world[1][j] - world[0][j]
                b[j] = world[2][j] - world[0][j]
            }

            normal := cross3(a, b)
            length := math.sqrt(
                normal[0] * normal[0] + normal[1] * normal[1] + normal[2] * normal[2],
            )
            light := 0.0
            if length > 0 {
                for j in 0 ..< 3 {
                    light += normal[j] / length * f32le(camera.data, w.cameraLightOffset + j * 4)
                }
            }

            intensity := ambient + (1 - ambient) * clamp(light, 0, 1)
            for &v in input {
                for &c in v.color {
                    c *= intensity
                }
            }
        }

        if accelerated { queue_triangle(t, input) }

        outside_any := u32(0)
        outside_all := u32(63)
        for vertex in input {
            code := u32(0)
            for plane in 0 ..< 6 {
                if clip_distance(vertex.p, plane) < 0 { code |= 1 << u32(plane) }
            }
            outside_any |= code
            outside_all &= code
        }
        if outside_all != 0 { continue }
        if outside_any == 0 {
            if !raster_triangle(t, input, camera.data) { return false }
            continue
        }

        poly: [CLIP_CAPACITY]Clip_Vertex
        copy(poly[:], input[:])
        count := 3
        for plane in 0 ..< 6 {
            next: [CLIP_CAPACITY]Clip_Vertex
            n := 0
            if count == 0 {
                break
            }

            previous := poly[count - 1]
            pd := clip_distance(previous.p, plane)
            for current in poly[:count] {
                cd := clip_distance(current.p, plane)
                if (pd >= 0) != (cd >= 0) {
                    if n ==
                       len(next) { return fail(t.registry, "clipped polygon capacity exceeded") }
                    next[n] = clip_lerp(previous, current, pd / (pd - cd))
                    n += 1
                }

                if cd >= 0 {
                    if n ==
                       len(next) { return fail(t.registry, "clipped polygon capacity exceeded") }
                    next[n] = current
                    n += 1
                }

                previous, pd = current, cd
            }

            poly, count = next, n
        }

        for i := 1; i + 1 < count; i += 1 {
            if !raster_triangle(t, {poly[0], poly[i], poly[i + 1]}, camera.data) {
                return false
            }
        }
    }

    return true
}

edge :: proc(a, b, p: [2]f64) -> f64 {
    return (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])
}

top_left :: proc(a, b: [2]f64) -> bool {
    return b[1] < a[1] || (b[1] == a[1] && b[0] > a[0])
}

// Inputs are finite clipped screen coordinates. Integer conversion is bounded
// by the display dimensions; these preserve round-away and floor/ceil exactly.
pixel_round :: proc(value: f64) -> f64 {
    return f64(int(value + 0.5)) if value >= 0 else f64(int(value - 0.5))
}
pixel_floor :: proc(value: f64) -> int {
    n := int(value)
    return n - 1 if f64(n) > value else n
}
pixel_ceil :: proc(value: f64) -> int {
    n := int(value)
    return n + 1 if f64(n) < value else n
}
project_pixel :: proc(point: [4]f64, width, height: int) -> [2]f64 {
    reciprocal := 1 / point[3]
    return {
        pixel_round((point[0] * reciprocal * 0.5 + 0.5) * f64(width) * w.meshSubpixelScale) /
        w.meshSubpixelScale,
        pixel_round((0.5 - point[1] * reciprocal * 0.5) * f64(height) * w.meshSubpixelScale) /
        w.meshSubpixelScale,
    }
}
triangle_bounds :: proc(p: [3][2]f64, clip: [4]i32, width, height: int) -> [4]int {
    return {
        max(pixel_floor(min(p[0][0], p[1][0], p[2][0])), int(clip[0]), 0),
        max(pixel_floor(min(p[0][1], p[1][1], p[2][1])), int(clip[1]), 0),
        min(pixel_ceil(max(p[0][0], p[1][0], p[2][0])), int(clip[0] + clip[2]), width),
        min(pixel_ceil(max(p[0][1], p[1][1], p[2][1])), int(clip[1] + clip[3]), height),
    }
}

raster_triangle :: proc(
    t: ^Transaction,
    triangle: [3]Clip_Vertex,
    camera: []u8,
    account := true,
) -> bool {
    target := image(t, t.render.target)
    depth := lookup(t, t.render.depth, .Depth)
    v := triangle
    p: [3][2]f64
    z, iw: [3]f64
    for q, i in v {
        if q.p[3] <= 0.000001 {
            return true
        }

        iw[i] = 1 / q.p[3]
        z[i] = q.p[2] * iw[i]
        // Quantized coverage avoids tiny native/Wasm differences at shared edges.
        p[i] = project_pixel(q.p, int(target.width), int(target.height))
    }

    area := edge(p[0], p[1], p[2])
    if area == 0 {
        return true
    }

    if area < 0 {
        p[1], p[2] = p[2], p[1]
        v[1], v[2] = v[2], v[1]
        z[1], z[2] = z[2], z[1]
        iw[1], iw[2] = iw[2], iw[1]
        area = -area
    }

    bounds := triangle_bounds(p, t.render.clip, int(target.width), int(target.height))
    x0, y0, x1, y1 := bounds[0], bounds[1], bounds[2], bounds[3]
    if x1 <= x0 || y1 <= y0 {
        return true
    }

    if account && !work(t, (x1 - x0) * (y1 - y0)) {
        return false
    }

    if len(t.gpu_vertices) != 0 { return true }

    fog_start := f32le(camera, w.cameraFogStartOffset)
    fog_end := f32le(camera, w.cameraFogEndOffset)
    fog_color := u32le(camera, w.cameraFogColorOffset)
    uniform := !account && v[0].color == v[1].color && v[0].color == v[2].color
    solid := u32(0xff000000)
    for c, channel in v[0].color {
        uniform = uniform && c == pixel_round(c)
        solid |= u32(clamp(pixel_round(c), 0, 255)) << u32(channel * 8)
    }

    for y in y0 ..< y1 {
        for x in x0 ..< x1 {
            sample := [2]f64{f64(x) + 0.5, f64(y) + 0.5}

            weights := [3]f64 {
                edge(p[1], p[2], sample),
                edge(p[2], p[0], sample),
                edge(p[0], p[1], sample),
            }

            inside := true
            for e, i in weights {
                if e < 0 || (e == 0 && !top_left(p[(i + 1) % 3], p[(i + 2) % 3])) {
                    inside = false
                }
            }

            if !inside {
                continue
            }

            for &b in weights {
                b /= area
            }

            dz := f64(f32(weights[0] * z[0] + weights[1] * z[1] + weights[2] * z[2]))
            offset := (y * int(target.width) + x) * 4
            if dz < 0 || dz >= f32le(depth.data, offset) {
                continue
            }

            if uniform && dz <= fog_start {
                putf(depth.data, offset, dz)
                put32(target.data, offset, solid)
                continue
            }

            reciprocal := weights[0] * iw[0] + weights[1] * iw[1] + weights[2] * iw[2]
            fog := clamp((dz - fog_start) / (fog_end - fog_start), 0, 1)
            color := u32(0xff000000)
            for channel in 0 ..< 3 {
                value := 0.0
                for b, i in weights {
                    value += b * iw[i] * v[i].color[channel]
                }

                value =
                    value / reciprocal * (1 - fog) +
                    f64((fog_color >> u32(channel * 8)) & 255) * fog
                color |= u32(clamp(math.round(value), 0, 255)) << u32(channel * 8)
            }

            putf(depth.data, offset, dz)
            put32(target.data, offset, color)
        }
    }

    return true
}

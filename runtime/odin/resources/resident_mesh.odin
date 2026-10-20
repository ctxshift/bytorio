package resources

import w "../resource_protocol"

Account_Vertex :: struct {
    point:   [4]f64,
    pixel:   [2]f64,
    outside: u32,
    valid:   bool,
}

// Keep logical work accounting on the CPU, independent of GPU/driver coverage.
// Transform each indexed position once; lighting and the rendered transform run
// in the cached GPU mesh program. CPU-only execution never enters this path.
resident_mesh :: proc(t: ^Transaction, mesh: ^Slot, model, view: Matrix, camera: ^Slot) -> bool {
    capacity := len(t.gpu_vertices) / size_of(Resident_Draw)
    if t.resident_count >= capacity { return fail(t.registry, "resident draw capacity exceeded") }
    draws := (cast([^]Resident_Draw)raw_data(t.gpu_vertices))[:capacity]
    draw := &draws[t.resident_count]
    draw^ = Resident_Draw {
        version      = mesh.gpu_version,
        data         = mesh.data[int(mesh.mesh_offset):],
        vertex_count = mesh.vertex_count,
        index_count  = mesh.index_count,
        ambient      = f32(f32le(camera.data, w.cameraAmbientOffset)),
    }
    if mesh.kind == .Voxel { draw.palette = lookup(t, mesh.link, .Palette).data }
    for i in 0 ..< 16 {
        draw.model[i], draw.view[i] = f32(model[i]), f32(view[i])
    }
    for i in 0 ..< 3 { draw.light[i] = f32(f32le(camera.data, w.cameraLightOffset + i * 4)) }
    t.resident_count += 1

    size := int(mesh.vertex_count) * size_of(Account_Vertex)
    scratch, ok := allocate(t, size, zero = false, alignment = align_of(Account_Vertex))
    if !ok { return false }
    defer { t.retained -= size; delete(scratch) }
    points := (cast([^]Account_Vertex)raw_data(scratch))[:mesh.vertex_count]
    target := image(t, t.render.target)
    for &vertex, i in points {
        at := i * w.meshVertexBytes
        vertex.point = matrix_point(
            view,
            matrix_point(
                model,
                {f32le(draw.data, at), f32le(draw.data, at + 4), f32le(draw.data, at + 8), 1},
            ),
        )
        vertex.outside = 0
        vertex.pixel = {}
        for plane in 0 ..< 6 {
            if clip_distance(vertex.point, plane) < 0 { vertex.outside |= 1 << u32(plane) }
        }
        vertex.valid = vertex.point[3] > 0.000001
        if vertex.valid && vertex.outside == 0 {
            vertex.pixel = project_pixel(vertex.point, int(target.width), int(target.height))
        }
    }
    indices := draw.data[int(mesh.vertex_count) * w.meshVertexBytes:]
    for at := 0; at < int(mesh.index_count) * w.meshIndexBytes; at += 12 {
        indexed: [3]Account_Vertex
        outside_any := u32(0)
        outside_all := u32(63)
        for &vertex, i in indexed {
            vertex = points[u32le(indices, at + i * 4)]
            outside_any |= vertex.outside
            outside_all &= vertex.outside
        }
        if outside_all != 0 { continue }
        if outside_any == 0 {
            if !indexed[0].valid || !indexed[1].valid || !indexed[2].valid { continue }
            p := [3][2]f64{indexed[0].pixel, indexed[1].pixel, indexed[2].pixel}
            if edge(p[0], p[1], p[2]) == 0 { continue }
            bounds := triangle_bounds(p, t.render.clip, int(target.width), int(target.height))
            if bounds[2] > bounds[0] &&
               bounds[3] > bounds[1] &&
               !work(t, (bounds[2] - bounds[0]) * (bounds[3] - bounds[1])) { return false }
            continue
        }
        poly: [CLIP_CAPACITY]Clip_Vertex
        for vertex, i in indexed { poly[i].p = vertex.point }
        count := 3
        for plane in 0 ..< 6 {
            if count == 0 { break }
            next: [CLIP_CAPACITY]Clip_Vertex
            n := 0
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
            if !raster_triangle(t, {poly[0], poly[i], poly[i + 1]}, camera.data) { return false }
        }
    }
    return true
}

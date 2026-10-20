package gpu

import resources "../../resources"
import gl "vendor:OpenGL"

GPU_CACHE_BYTES :: 64 * 1024 * 1024
GPU_CACHE_ENTRIES :: 1024
RESIDENT_VERTEX_FLOATS :: 12
Cached_Mesh :: struct {
    buffer:  u32,
    bytes:   int,
    palette: []u8,
}

clear_meshes :: proc() {
    for _, mesh in device.cache {
        buffer := mesh.buffer
        gl.DeleteBuffers(1, &buffer)
        delete(mesh.palette)
    }
    delete(device.cache)
    device.cache = nil
    device.cache_bytes = 0
}

cached_mesh :: proc(draw: resources.Resident_Draw) -> (u32, bool) {
    entry, exists := device.cache[draw.version]
    same := exists && len(entry.palette) == len(draw.palette)
    if same {
        for value, i in draw.palette {
            if entry.palette[i] != value { same = false; break }
        }
    }
    if same { device.cache_hits += 1; return entry.buffer, true }
    size := int(draw.index_count) * RESIDENT_VERTEX_FLOATS * size_of(f32)
    if size > GPU_CACHE_BYTES { return 0, false }
    if device.cache_bytes + size > GPU_CACHE_BYTES || len(device.cache) >= GPU_CACHE_ENTRIES {
        clear_meshes()
        exists = false
    }
    vertices := make([]f32, int(draw.index_count) * RESIDENT_VERTEX_FLOATS)
    defer delete(vertices)
    indices := draw.data[int(draw.vertex_count) * 16:]
    for triangle := 0; triangle < int(draw.index_count); triangle += 3 {
        points: [3][3]f32
        colors: [3]u32
        for i in 0 ..< 3 {
            at := int(resources.u32le(indices, (triangle + i) * 4)) * 16
            for axis in 0 ..< 3 { points[i][axis] = f32(resources.f32le(draw.data, at + axis * 4)) }
            colors[i] = resources.u32le(draw.data, at + 12)
            if len(draw.palette) !=
               0 { colors[i] = resources.u32le(draw.palette, int(colors[i]) * 4) }
        }
        for i in 0 ..< 3 {
            at := (triangle + i) * RESIDENT_VERTEX_FLOATS
            for axis in 0 ..< 3 {
                vertices[at + axis] = points[i][axis]
                vertices[at + 3 + axis] = f32((colors[i] >> u32(axis * 8)) & 255) / 255
                vertices[at + 6 + axis] = points[1][axis] - points[0][axis]
                vertices[at + 9 + axis] = points[2][axis] - points[0][axis]
            }
        }
    }
    buffer: u32
    gl.GenBuffers(1, &buffer)
    gl.BindBuffer(gl.ARRAY_BUFFER, buffer)
    gl.BufferData(gl.ARRAY_BUFFER, size, raw_data(vertices), gl.STATIC_DRAW)
    if gl.GetError() != gl.NO_ERROR { gl.DeleteBuffers(1, &buffer); return 0, false }
    if exists {
        gl.DeleteBuffers(1, &entry.buffer)
        device.cache_bytes -= entry.bytes
        delete(entry.palette)
    }
    if device.cache == nil { device.cache = make(map[u64]Cached_Mesh) }
    palette := make([]u8, len(draw.palette))
    copy(palette, draw.palette)
    device.cache[draw.version] = {buffer, size, palette}
    device.cache_bytes += size
    device.upload_bytes += u64(size)
    device.mesh_uploads += 1
    return buffer, true
}

resident_draw :: proc(value: resources.Resident_Draw, width, height, border: int) -> bool {
    draw := value
    buffer, ok := cached_mesh(draw)
    if !ok { return false }
    gl.BindVertexArray(device.resident_vao)
    gl.BindBuffer(gl.ARRAY_BUFFER, buffer)
    for i in 0 ..< 4 {
        gl.EnableVertexAttribArray(u32(i))
        gl.VertexAttribPointer(
            u32(i),
            3,
            gl.FLOAT,
            gl.FALSE,
            RESIDENT_VERTEX_FLOATS * 4,
            uintptr(i * 12),
        )
    }
    gl.UseProgram(device.resident)
    gl.UniformMatrix4fv(
        gl.GetUniformLocation(device.resident, "model"),
        1,
        gl.FALSE,
        &draw.model[0],
    )
    gl.UniformMatrix4fv(gl.GetUniformLocation(device.resident, "view"), 1, gl.FALSE, &draw.view[0])
    gl.Uniform3fv(gl.GetUniformLocation(device.resident, "light"), 1, &draw.light[0])
    gl.Uniform1f(gl.GetUniformLocation(device.resident, "ambient"), draw.ambient)
    gl.Uniform2f(gl.GetUniformLocation(device.resident, "logicalSize"), f32(width), f32(height))
    gl.Uniform1i(gl.GetUniformLocation(device.resident, "border"), i32(border))
    gl.DrawArrays(gl.TRIANGLES, 0, i32(draw.index_count))
    return true
}

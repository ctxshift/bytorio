package resources

import w "../resource_protocol"
import "core:mem"

// Host-only execution seam. Vertices are owned, lit clip-space triangles;
// callbacks may write only the transaction's copy-on-write attachments.
// The callback is synchronous and must not retain any supplied pointer.
Raster_Job :: struct {
    texture:            Texture_View,
    draws:              []Resident_Draw,
    vertices:           []u8,
    color, depth:       []u8,
    border:             []u8,
    width, height:      int,
    clip:               [4]i32,
    fog_color:          u32,
    fog_start, fog_end: f32,
}
Resident_Draw :: struct {
    textured:                  bool,
    version:                   u64,
    data, palette:             []u8,
    vertex_count, index_count: u32,
    model, view:               [16]f32,
    light:                     [3]f32,
    ambient:                   f32,
}

// Borrowed for one synchronous execution; immutable within a draw commit.
Texture_View :: struct {
    pixels:               []u8,
    version:              u64,
    width, height:        u32,
    address_u, address_v: u32,
}

raster_stride :: proc(texture: Texture_View) -> int {
    return TEXTURED_RASTER_VERTEX_BYTES if len(texture.pixels) != 0 else RASTER_VERTEX_BYTES
}

mesh_version :: proc(r: ^Registry) -> u64 {
    // A failed transaction may consume an ID; IDs are never reused by reset.
    assert(r.gpu_serial != max(u64))
    r.gpu_serial += 1
    return r.gpu_serial
}
Raster_Proc :: proc(job: Raster_Job) -> bool
RASTER_VERTEX_BYTES :: 7 * 4
TEXTURED_RASTER_VERTEX_BYTES :: 9 * 4
RASTER_STAGING_BYTES :: w.maxTrianglesPerCommit * 3 * RASTER_VERTEX_BYTES

flush_raster :: proc(t: ^Transaction) -> bool {
    if len(t.gpu_vertices) == 0 { return true }
    defer {
        t.retained -= len(t.gpu_vertices)
        delete(t.gpu_vertices)
        t.gpu_vertices = nil
        t.gpu_count = 0
        t.resident_count = 0
        t.gpu_texture = {}
    }
    target := owned(t, t.render.target)
    depth := mesh_owned(t, t.render.depth, .Depth)
    camera := lookup(t, t.render.camera, .Camera)
    if target == nil || depth == nil || camera == nil { return false }
    border: []u8
    if t.render.target == 0 {
        t.screen_gpu_batches += 1
        if t.screen_gpu_batches > 1 { t.preview_disabled = true }
        full_clip := t.render.clip == [4]i32{0, 0, i32(target.width), i32(target.height)}
        size := (int(target.width) + 2) * (int(target.height) + 2) * 4
        mask_size := int(target.width) * int(target.height)
        if t.registry.smooth_pan &&
           t.registry.pixel_snap &&
           t.gpu_ortho &&
           full_clip &&
           !t.preview_disabled {
            // Optional host presentation storage is bounded by the two screen
            // modes, separate from the cartridge's resource allocation budget.
            pointer, error := mem.alloc(size, 4)
            if error == nil {
                border = (cast([^]u8)pointer)[:size]
                mask, mask_error := mem.alloc(mask_size, 1)
                if mask_error == nil {
                    t.preview_mask = (cast([^]u8)mask)[:mask_size]
                    mem.zero(mask, mask_size)
                    t.preview = border
                } else {
                    delete(border)
                    border = nil
                }
            }
        }
    }
    job := Raster_Job {
        texture   = t.gpu_texture,
        vertices  = t.gpu_vertices[:t.gpu_count],
        color     = target.data,
        depth     = depth.data,
        border    = border,
        width     = int(target.width),
        height    = int(target.height),
        clip      = t.render.clip,
        fog_color = u32le(camera.data, w.cameraFogColorOffset),
        fog_start = f32(f32le(camera.data, w.cameraFogStartOffset)),
        fog_end   = f32(f32le(camera.data, w.cameraFogEndOffset)),
    }
    if t.resident_count != 0 {
        job.vertices = nil
        job.draws = (cast([^]Resident_Draw)raw_data(t.gpu_vertices))[:t.resident_count]
    }
    if !t.registry.rasterizer(job) {
        return fail(t.registry, "GPU raster execution failed; transaction discarded")
    }
    return true
}

prepare_raster :: proc(t: ^Transaction, texture := Texture_View{}) -> bool {
    if t.registry.rasterizer == nil { return false }
    if len(t.gpu_vertices) != 0 { return true }
    // Quality preferences must not make an otherwise valid resource packet
    // exceed its budget: use the reference rasterizer when staging cannot fit.
    size :=
        w.maxCommands * size_of(Resident_Draw) if t.registry.resident_meshes else w.maxTrianglesPerCommit * 3 * raster_stride(texture)
    if size > t.budget - t.retained { return false }
    bytes, ok := allocate(t, size, zero = false, alignment = align_of(Resident_Draw))
    if !ok {
        t.registry.error = ""
        return false
    }
    t.gpu_vertices = bytes
    t.gpu_texture = texture
    return true
}

queue_triangle :: proc(t: ^Transaction, vertices: [3]Clip_Vertex) {
    for vertex in vertices {
        for value in vertex.p {
            putf(t.gpu_vertices, t.gpu_count, value)
            t.gpu_count += 4
        }
        for value in vertex.color {
            putf(t.gpu_vertices, t.gpu_count, value)
            t.gpu_count += 4
        }
        if len(t.gpu_texture.pixels) != 0 {
            for value in vertex.uv {
                putf(t.gpu_vertices, t.gpu_count, value)
                t.gpu_count += 4
            }
        }
    }
}

package main

import gpu "../../../runtime/odin/gpu/native"
import r "../../../runtime/odin/resources"
import "core:fmt"
import "core:os"

main :: proc() {
    if !gpu.open(1) { fmt.eprintln("GPU initialization failed"); os.exit(1) }
    defer gpu.close()
    color := make([]u8, 32 * 32 * 4)
    depth := make([]u8, len(color))
    defer delete(color)
    defer delete(depth)
    for at := 0; at < len(depth); at += 4 { r.putf(depth, at, 1) }
    vertices := [21]f32 {
        -0.8,
        -0.8,
        0.25,
        1,
        255,
        0,
        0,
        0,
        0.8,
        0.25,
        1,
        255,
        0,
        0,
        0.8,
        -0.8,
        0.25,
        1,
        255,
        0,
        0,
    }
    bytes := (cast([^]u8)&vertices[0])[:size_of(vertices)]
    job := r.Raster_Job {
        vertices  = bytes,
        color     = color,
        depth     = depth,
        width     = 32,
        height    = 32,
        clip      = {0, 0, 32, 32},
        fog_color = 0xff000000,
        fog_start = 1,
        fog_end   = 2,
    }
    if !gpu.raster(job) { fmt.eprintln("GPU raster failed"); os.exit(1) }
    pixel := r.u32le(color, (16 * 32 + 16) * 4)
    z := r.f32le(depth, (16 * 32 + 16) * 4)
    fmt.printf("{{\"pixel\":%d,\"depth\":%.6f}}\n", pixel, z)
    if pixel != 0xff0000ff || z < 0.24999 || z > 0.25001 { os.exit(1) }
    mesh := make([]u8, 3 * 16 + 3 * 4)
    defer delete(mesh)
    for i in 0 ..< 3 {
        for axis in 0 ..< 3 { r.putf(mesh, i * 16 + axis * 4, f64(vertices[i * 7 + axis])) }
        r.put32(mesh, i * 16 + 12, 0xff0000ff)
        r.put32(mesh, 48 + i * 4, u32(i))
    }
    identity := [16]f32{1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}
    draw := r.Resident_Draw {
        version      = 1,
        data         = mesh,
        vertex_count = 3,
        index_count  = 3,
        model        = identity,
        view         = identity,
        ambient      = 1,
    }
    job.vertices = nil
    job.draws = []r.Resident_Draw{draw}
    for _ in 0 ..< 2 {
        for &value in color { value = 0 }
        for at := 0; at < len(depth); at += 4 { r.putf(depth, at, 1) }
        if !gpu.raster(job) ||
           r.u32le(color, (16 * 32 + 16) * 4) != 0xff0000ff ||
           r.f32le(depth, (16 * 32 + 16) * 4) != 0.25 { os.exit(1) }
    }
    counts := gpu.statistics()
    if counts != ([3]u64{1, 1, 144}) { os.exit(1) }
    job.draws[0].ambient = 0
    job.draws[0].light = {0, 0, -0.5}
    for at := 0; at < len(depth); at += 4 { r.putf(depth, at, 1) }
    if !gpu.raster(job) || r.u32le(color, (16 * 32 + 16) * 4) != 0xff000080 { os.exit(1) }
    palette := make([]u8, 1024)
    defer delete(palette)
    for i in 0 ..< 3 { r.put32(mesh, i * 16 + 12, 1) }
    job.draws[0].version = 2
    job.draws[0].palette = palette
    job.draws[0].ambient = 1
    for expected in ([2]u32{0xff00ff00, 0xffff0000}) {
        r.put32(palette, 4, expected)
        for at := 0; at < len(depth); at += 4 { r.putf(depth, at, 1) }
        if !gpu.raster(job) || r.u32le(color, (16 * 32 + 16) * 4) != expected { os.exit(1) }
    }
    if gpu.statistics()[0] != 3 { os.exit(1) }

    // Independent presentation orientation, residual and HUD expectations.
    registry: r.Registry
    registry.preview_enabled = true
    registry.preview = make([]u8, 322 * 182 * 4)
    registry.preview_mask = make([]u8, 320 * 180)
    defer delete(registry.preview)
    defer delete(registry.preview_mask)
    registry.preview_background = 0xff000000
    registry.preview_residual[0] = 1.0 / 6.0
    for y in 0 ..< 182 {
        for x in 0 ..< 322 { r.put32(registry.preview, (y * 322 + x) * 4, 0xff000000 | u32(x % 256) | u32(y % 256) << 8) }
    }
    output := make([]u32, 320 * 180)
    defer delete(output)
    registry.preview_mask[90 * 320 + 160] = 1
    output[90 * 320 + 160] = 0xffff00ff
    if !gpu.present(&registry, output, 320, 180, 1920, 1080) { os.exit(1) }
    capture := gpu.capture_presentation()
    defer delete(capture)
    if r.u32le(capture, (100 * 1920 + 101) * 4) != 0xff001112 ||
       r.u32le(capture, (540 * 1920 + 960) * 4) != 0xffff00ff { os.exit(1) }
}

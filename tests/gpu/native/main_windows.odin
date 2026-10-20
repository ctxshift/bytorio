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
}

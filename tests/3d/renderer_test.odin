package mesh_test

import abi "../../runtime/odin/abi"
import core "../../runtime/odin/core"
import presentation "../../runtime/odin/presentation"
import w "../../runtime/odin/resource_protocol"
import r "../../runtime/odin/resources"
import gfx "../../sdk/odin/gfx"
import g "../../sdk/odin/gfx3d"
import t "../../sdk/odin/resource"
import "core:math"
import "core:testing"

commit :: proc(
    test: ^testing.T,
    registry: ^r.Registry,
    expected := true,
    budget := w.maxResourceBytes,
) {
    t.end()
    testing.expect(test, t.commit() != 0, t.error)
    accepted := r.submit(registry, t.packet[:int(t.packet_size())], budget, abi.DISPLAY_LOW)
    testing.expect(test, accepted == expected, registry.error)
    testing.expect(test, t.ack(t.sequence))
}

triangle :: proc(z: f32, color: u32) -> g.Mesh {
    v := [3]g.Vertex {
        {
            {-0.8, -0.8, z},
            color,
        },
        {
            {0, 0.8, z},
            color,
        },
        {
            {0.8, -0.8, z},
            color,
        },
    }

    indices := [3]u32{0, 1, 2}

    return g.mesh(v[:], indices[:])
}

camera :: proc() -> g.Camera {
    return g.camera({
        view_projection = g.identity(),
        ambient         = 1,
        fog_color       = 0xff000000,
        fog_start       = 1,
        fog_end         = 2,
    })
}

mesh_depth_and_ownership :: proc(test: ^testing.T) {
    registry: r.Registry
    defer r.close(&registry)
    testing.expect(test, r.reset(&registry, 501))
    testing.expect(test, t.configure(501))
    t.begin(0)
    depth := g.depth(320, 180)
    view := camera()
    near := triangle(0.25, 0xff0000ff)
    far := triangle(0.75, 0xff00ff00)
    equal := triangle(0.25, 0xffff0000)
    commit(test, &registry)
    t.begin_draw(0)
    pass := gfx.begin_pass(gfx.screen(), {
        clear = true,
        color = 0xff222222,
    })
    g.bind(pass, depth, view)
    g.draw(pass, near)
    g.draw(pass, far)
    g.draw(pass, equal)
    gfx.end_pass(pass)
    gfx.present(gfx.screen())
    commit(test, &registry)
    testing.expect_value(test, registry.output[90 * 320 + 160], u32(0xff0000ff))
    testing.expect_value(test, registry.output[0], u32(0xff222222))
    testing.expect_value(test, registry.stats.triangles, u64(3))
    // A bad command after a depth/color clear must roll back the complete packet.
    bytes := registry.bytes
    center_depth := r.u32le(
        registry.slots[(depth.id & w.handleIndexMask) - 1].data,
        (90 * 320 + 160) * 4,
    )
    t.begin_draw(0)
    pass = gfx.begin_pass(gfx.screen(), {
        clear = true,
        color = 0xff00ff00,
    })
    g.bind(pass, depth, view)
    invalid := g.identity()
    invalid[0] = transmute(f32)u32(0x7fc00000)
    g.draw(pass, near, invalid)
    gfx.end_pass(pass)
    gfx.present(gfx.screen())
    commit(test, &registry, false)
    testing.expect_value(test, registry.bytes, bytes)
    testing.expect_value(test, registry.output[90 * 320 + 160], u32(0xff0000ff))
    testing.expect_value(
        test,
        r.u32le(registry.slots[(depth.id & w.handleIndexMask) - 1].data, (90 * 320 + 160) * 4),
        center_depth,
    )
    // Fresh sessions invalidate old SDK handles and restart sequence/ownership.
    testing.expect(test, r.reset(&registry, 502))
    testing.expect(test, t.configure(502))
    t.begin(0)
    g.destroy(near)
    testing.expect(test, t.error != "")
    t.end()
    testing.expect(test, t.configure(503))
    testing.expect(test, r.reset(&registry, 503, 4))
    t.begin(0)
    _ = g.depth(320, 180)
    commit(test, &registry, false)
}

voxel_surfaces_and_atomic_edits :: proc(test: ^testing.T) {
    registry: r.Registry
    defer r.close(&registry)
    testing.expect(test, r.reset(&registry, 601))
    testing.expect(test, t.configure(601))
    t.begin(0)
    colors: [256]u32
    colors[1] = 0xff00ffff
    palette := gfx.palette(colors[:])
    cells := [2]u8{1, 1}

    volume := g.voxel(2, 1, 1, palette, cells[:])
    commit(test, &registry)
    testing.expect_value(test, registry.stats.voxel_faces, u64(10))
    testing.expect_value(
        test,
        registry.slots[(volume.id & w.handleIndexMask) - 1].index_count,
        u32(60),
    )
    t.begin(1)
    empty := [1]u8{0}

    g.edit(volume, 1, 0, 0, 1, 1, 1, empty[:])
    commit(test, &registry)
    testing.expect_value(test, registry.stats.voxel_faces, u64(16))
    testing.expect_value(
        test,
        registry.slots[(volume.id & w.handleIndexMask) - 1].index_count,
        u32(36),
    )
    old_hash, old_bytes := r.hash(&registry), registry.bytes
    t.begin(2)
    g.edit(volume, 0, 0, 0, 1, 1, 1, empty[:])
    g.edit(volume, 2, 0, 0, 1, 1, 1, empty[:])
    commit(test, &registry, false)
    testing.expect_value(test, r.hash(&registry), old_hash)
    testing.expect_value(test, registry.bytes, old_bytes)
    testing.expect(test, r.reset(&registry, 602))
    testing.expect(test, t.configure(602))
    t.begin(0)
    // Finite source dimensions do not imply a safe surface or staging size.
    _ = g.depth(320, 180)
    commit(test, &registry, false, 128)
    testing.expect_value(test, registry.bytes, 0)
}

homogeneous_clipping_and_indices :: proc(test: ^testing.T) {
    registry: r.Registry
    defer r.close(&registry)
    testing.expect(test, r.reset(&registry, 701))
    testing.expect(test, t.configure(701))
    t.begin(0)
    depth := g.depth(320, 180)
    view := camera()
    v := [3]g.Vertex {
        {
            {-4, -0.8, -0.5},
            0xff0000ff,
        },
        {
            {0, 4, 0.5},
            0xff0000ff,
        },
        {
            {4, -0.8, 0.5},
            0xff0000ff,
        },
    }

    indices := [3]u32{0, 1, 2}

    mesh := g.mesh(v[:], indices[:])
    commit(test, &registry)
    t.begin_draw(0)
    pass := gfx.begin_pass(gfx.screen(), {
        clear = true,
        color = 0xff000000,
    })
    g.bind(pass, depth, view)
    g.draw(pass, mesh)
    gfx.end_pass(pass)
    gfx.present(gfx.screen())
    commit(test, &registry)
    colored := 0
    for p in registry.output {
        if p == 0xff0000ff {
            colored += 1
        }
    }

    testing.expect(
        test,
        colored > 1000 && colored < 320 * 180,
        "partially clipped triangle remains visible",
    )
    t.begin(1)
    outside: [6]g.Mesh
    for plane in 0 ..< 6 {
        points := [3]g.Vertex {
            {{-0.8, -0.8, 0.5}, 0xff0000ff},
            {{0, 0.8, 0.5}, 0xff0000ff},
            {{0.8, -0.8, 0.5}, 0xff0000ff},
        }
        axis := plane / 2
        distance := f32(-2) if plane % 2 == 0 else f32(2)
        for &vertex in points { vertex.position[axis] = distance }
        outside[plane] = g.mesh(points[:], indices[:])
    }
    commit(test, &registry)
    t.begin_draw(1)
    pass = gfx.begin_pass(gfx.screen(), {clear = true, color = 0xff000000})
    g.bind(pass, depth, view)
    for geometry in outside { g.draw(pass, geometry) }
    gfx.end_pass(pass)
    gfx.present(gfx.screen())
    commit(test, &registry)
    for p in registry.output { testing.expect_value(test, p, u32(0xff000000)) }
    testing.expect(test, r.reset(&registry, 702))
    testing.expect(test, t.configure(702))
    t.begin(0)
    indices[2] = 3
    _ = g.mesh(v[:], indices[:])
    commit(test, &registry, false)
    testing.expect_value(test, registry.bytes, 0)
}

voxel_limits_and_palette_lifetime :: proc(test: ^testing.T) {
    registry: r.Registry
    defer r.close(&registry)
    colors: [256]u32
    colors[1] = 0xff00ffff
    testing.expect(test, r.reset(&registry, 801))
    testing.expect(test, t.configure(801))
    t.begin(0)
    palette := gfx.palette(colors[:])
    cells := [2]u8{1, 1}
    _ = g.voxel(2, 1, 1, palette, cells[:])
    commit(test, &registry)
    previous := r.hash(&registry)
    t.begin(1)
    transparent: [4]u8
    gfx.write(palette, 4, transparent[:])
    commit(test, &registry, false)
    testing.expect_value(test, r.hash(&registry), previous)

    testing.expect(test, r.reset(&registry, 802))
    testing.expect(test, t.configure(802))
    t.begin(0)
    palette = gfx.palette(colors[:])
    _ = g.voxel(2, 1, 1, palette, cells[:])
    commit(test, &registry)
    previous = r.hash(&registry)
    t.begin(1)
    gfx.destroy(palette)
    commit(test, &registry, false)
    testing.expect_value(test, r.hash(&registry), previous)

    testing.expect(test, r.reset(&registry, 803))
    testing.expect(test, t.configure(803))
    t.begin(0)
    palette = gfx.palette(colors[:])
    checker := make([]u8, 32 * 32 * 32)
    defer delete(checker)
    for z in 0 ..< 32 {
        for y in 0 ..< 32 {
            for x in 0 ..< 32 { checker[(z * 32 + y) * 32 + x] = u8((x + y + z) % 2) }
        }
    }
    _ = g.voxel(32, 32, 32, palette, checker)
    commit(test, &registry, false)
    testing.expect_value(test, registry.bytes, 0)
    testing.expect(test, registry.error == "voxel surface limit exceeded")

    testing.expect(test, r.reset(&registry, 804))
    testing.expect(test, t.configure(804))
    t.begin(0)
    palette = gfx.palette(colors[:])
    for &cell in checker { cell = 1 }
    for _ in 0 ..< 5 { _ = g.voxel(32, 32, 32, palette, checker) }
    commit(test, &registry, false)
    testing.expect_value(test, registry.bytes, 0)
    testing.expect(test, registry.error == "voxel rebuild work limit exceeded")
}

// SDK packet staging is session-global; exercise these cases sequentially.
device_calls: int
device_failure: bool
test_device :: proc(job: r.Raster_Job) -> bool {
    device_calls += 1
    if len(job.texture.pixels) != 0 { return r.software_raster(job) }
    if device_resident {
        if len(job.vertices) != 0 ||
           len(job.draws) != 2 ||
           job.draws[0].version == 0 ||
           job.draws[0].version != job.draws[1].version { return false }
    } else if len(job.vertices) != 2 * 3 * r.RASTER_VERTEX_BYTES { return false }
    r.put32(job.color, 0, 0xff00ffff)
    r.put32(job.color, (90 * 320 + 160) * 4, 0xff00ffff)
    for at := 0; at < len(job.border); at += 4 { r.put32(job.border, at, 0xff00ffff) }
    return !device_failure
}

device_resident: bool

raster_device_transactions :: proc(test: ^testing.T, resident := false, shift := 0.0) -> u64 {
    registry: r.Registry
    defer r.close(&registry)
    testing.expect(test, r.reset(&registry, 901))
    testing.expect(test, t.configure(901))
    t.begin(0)
    depth := g.depth(320, 180)
    view := camera()
    mesh := triangle(0.25, 0xff0000ff)
    commit(test, &registry)
    registry.rasterizer = test_device
    registry.resident_meshes = resident
    device_resident = resident
    registry.smooth_pan, registry.pixel_snap = true, true
    device_calls = 0
    device_failure = false
    t.begin_draw(0)
    pass := gfx.begin_pass(gfx.screen(), {clear = true, color = 0xff222222})
    g.bind(pass, depth, view)
    g.draw(pass, mesh, g.pose(shift, 0, 0, 0, 1))
    g.draw(pass, mesh, g.pose(shift, 0, 0, 0, 1))
    // CPU composition must observe the completed GPU batch before continuing.
    gfx.rect(pass, 159, 89, 2, 2, 0xff0000ff)
    gfx.end_pass(pass)
    gfx.present(gfx.screen())
    commit(test, &registry)
    testing.expect_value(test, device_calls, 1)
    charged_work := registry.stats.pixel_work
    testing.expect(test, registry.preview_enabled)
    testing.expect_value(test, registry.preview_mask[90 * 320 + 160], u8(1))
    testing.expect_value(test, registry.output[0], u32(0xff00ffff))
    testing.expect_value(test, registry.output[90 * 320 + 160], u32(0xff0000ff))
    previous := r.hash(&registry)
    previous_preview := raw_data(registry.preview)
    device_failure = true
    t.begin_draw(0)
    pass = gfx.begin_pass(gfx.screen(), {clear = true, color = 0xff333333})
    g.bind(pass, depth, view)
    g.draw(pass, mesh)
    g.draw(pass, mesh)
    gfx.end_pass(pass)
    gfx.present(gfx.screen())
    commit(test, &registry, false)
    testing.expect_value(test, device_calls, 2)
    testing.expect_value(test, r.hash(&registry), previous)
    testing.expect(test, raw_data(registry.preview) == previous_preview)

    // Optional GPU staging must not reject a CPU-valid low-memory packet.
    testing.expect(test, r.reset(&registry, 902))
    testing.expect(test, t.configure(902))
    registry.resident_meshes = false
    device_resident = false
    t.begin(0)
    depth = g.depth(320, 180)
    view = camera()
    mesh = triangle(0.25, 0xff0000ff)
    commit(test, &registry)
    t.begin_draw(0)
    pass = gfx.begin_pass(gfx.screen(), {clear = true, color = 0xff222222})
    g.bind(pass, depth, view)
    g.draw(pass, mesh)
    gfx.end_pass(pass)
    gfx.present(gfx.screen())
    commit(test, &registry, budget = 2 * 1024 * 1024)
    testing.expect_value(test, device_calls, 2)
    testing.expect_value(test, registry.output[90 * 320 + 160], u32(0xff0000ff))
    testing.expect(test, !registry.preview_enabled)
    return charged_work
}

presentation_grid_and_hud :: proc(test: ^testing.T) {
    registry: r.Registry
    defer r.close(&registry)
    testing.expect(test, core.set_display(abi.DISPLAY_LOW))
    registry.has_output, registry.preview_enabled = true, true
    registry.output_width, registry.output_height = 320, 180
    registry.output = make([]u32, 320 * 180)
    registry.preview_mask = make([]u8, 320 * 180)
    registry.preview = make([]u8, 322 * 182 * 4)
    registry.preview_background = 0xff000000
    for y in 0 ..< 182 {
        for x in 0 ..< 322 { r.put32(registry.preview, (y * 322 + x) * 4, 0xff000000 | u32(x % 256) | u32(y % 256) << 8) }
    }
    hud := 90 * 320 + 160
    registry.preview_mask[hud] = 1
    registry.output[hud] = 0xffff00ff
    state: presentation.State
    defer presentation.close(&state)
    first := presentation.prepare(&state, &registry, 1920, 1080)
    saved := make([]u32, len(first))
    defer delete(saved)
    copy(saved, first)
    testing.expect_value(test, state.width, 1920)
    registry.preview_residual[0] = 1.0 / 6.0
    second := presentation.prepare(&state, &registry, 1920, 1080)
    testing.expect_value(test, second[100 * 1920 + 100], saved[100 * 1920 + 101])
    for x in 160 * 6 ..< 161 * 6 {
        testing.expect_value(test, second[(90 * 6) * 1920 + x], u32(0xffff00ff))
    }
    registry.preview_enabled = false
    _ = presentation.prepare(&state, &registry, 1920, 1080)
    testing.expect(test, !state.active)
    testing.expect_value(test, state.width, 320)
}

presentation_matches_independent_pixel_reference :: proc(test: ^testing.T) {
    for width in ([2]int{320, 640}) {
        registry: r.Registry
        height := width * 9 / 16
        testing.expect(
            test,
            core.set_display(abi.DISPLAY_LOW if width == 320 else abi.DISPLAY_HIGH),
        )
        registry.has_output, registry.preview_enabled = true, true
        registry.output_width, registry.output_height = width, height
        registry.output = make([]u32, width * height)
        registry.preview_mask = make([]u8, width * height)
        registry.preview = make([]u8, (width + 2) * (height + 2) * 4)
        registry.preview_background = 0xff332211
        for y in 0 ..< height + 2 {
            for x in 0 ..< width + 2 {
                color := u32(0x80100000) | u32(x % 128) | u32(y % 128) << 8
                r.put32(registry.preview, (y * (width + 2) + x) * 4, color)
            }
        }
        for y in 0 ..< height {
            for x in 0 ..< width {
                at := y * width + x
                registry.preview_mask[at] = 1 if (x + y) % 7 == 0 else 0
                registry.output[at] = 0xff123456
            }
        }
        state: presentation.State
        for scale in ([3]int{2, 3, 6}) {
            if width == 640 && scale == 6 { continue }
            for sign in ([2]f64{-1, 1}) {
                registry.preview_residual = {sign * 1.49 / f64(scale), -sign * 1.49 / f64(scale)}
                pixels := presentation.prepare(&state, &registry, width * scale, height * scale)
                dx := math.round(registry.preview_residual[0] * f64(scale)) / f64(scale)
                dy := math.round(registry.preview_residual[1] * f64(scale)) / f64(scale)
                same := true
                for y in 0 ..< height * scale {
                    for x in 0 ..< width * scale {
                        at := (y / scale) * width + x / scale
                        expected := registry.output[at]
                        if registry.preview_mask[at] == 0 {
                            sx := int(math.floor((f64(x) + 0.5) / f64(scale) + 1 + dx))
                            sy := int(math.floor((f64(y) + 0.5) / f64(scale) + 1 + dy))
                            expected = r.over(
                                r.u32le(registry.preview, (sy * (width + 2) + sx) * 4),
                                registry.preview_background,
                            )
                        }
                        same = same && pixels[y * width * scale + x] == expected
                    }
                }
                testing.expect(
                    test,
                    same,
                    "integer presentation must preserve every reference pixel, including shifted HUD boundaries",
                )
            }
        }
        presentation.close(&state)
        r.close(&registry)
    }
}

@(test)
software_quality :: proc(test: ^testing.T) {
    defer r.software_close()
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
    r.software_configure(2)
    testing.expect(test, r.software_raster(job))
    testing.expect_value(test, r.u32le(color, (16 * 32 + 16) * 4), u32(0xff0000ff))
    testing.expect_value(test, r.f32le(depth, (16 * 32 + 16) * 4), 0.25)
    partial := false
    for at := 0; at < len(color); at += 4 {
        alpha := color[at + 3]
        partial = partial || alpha > 0 && alpha < 255
    }
    testing.expect(test, partial)
    device := r.software_device
    for y in 0 ..< 2 {
        for x in 0 ..< 2 {
            r.put32(
                device.color,
                (y * device.width + x) * 4,
                0xffffffff if (x + y) % 2 == 0 else 0xff000000,
            )
        }
    }
    filtered, _ := r.software_resolve(device, 0, 0, device.width, 2)
    testing.expect_value(test, filtered, u32(0xffbcbcbc))
    testing.expect(test, r.software_storage_bytes() > 0)
    r.software_close()
    testing.expect_value(test, r.software_storage_bytes(), 0)
}

@(test)
shared_3d :: proc(test: ^testing.T) {
    resident_attachment_sequences(test)
    textured_sampling_and_depth(test)
    billboard_pivots_and_axes(test)
    cutout_color_and_depth_holes(test)
    cutout_invalid_descriptors_roll_back(test)
    textured_resource_ownership(test)
    textured_creation_rejects_old_protocols_and_invalid_data(test)
    material_texture_edits_and_budget_rollback(test)
    mesh_depth_and_ownership(test)
    voxel_surfaces_and_atomic_edits(test)
    homogeneous_clipping_and_indices(test)
    voxel_limits_and_palette_lifetime(test)
    streamed_work := raster_device_transactions(test)
    resident_work := raster_device_transactions(test, true)
    testing.expect_value(test, resident_work, streamed_work)
    clipped_streamed := raster_device_transactions(test, false, 0.9)
    clipped_resident := raster_device_transactions(test, true, 0.9)
    testing.expect_value(test, clipped_resident, clipped_streamed)
    presentation_grid_and_hud(test)
    presentation_matches_independent_pixel_reference(test)
}

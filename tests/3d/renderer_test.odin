package mesh_test

import abi "../../runtime/odin/abi"
import w "../../runtime/odin/resource_protocol"
import r "../../runtime/odin/resources"
import gfx "../../sdk/odin/gfx"
import g "../../sdk/odin/gfx3d"
import t "../../sdk/odin/resource"
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
@(test)
shared_3d :: proc(test: ^testing.T) {
    mesh_depth_and_ownership(test)
    voxel_surfaces_and_atomic_edits(test)
    homogeneous_clipping_and_indices(test)
    voxel_limits_and_palette_lifetime(test)
}

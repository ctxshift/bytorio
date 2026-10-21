package mesh_test

import w "../../runtime/odin/resource_protocol"
import r "../../runtime/odin/resources"
import data "../../sdk/odin/data"
import gfx "../../sdk/odin/gfx"
import g "../../sdk/odin/gfx3d"
import t "../../sdk/odin/resource"
import "core:testing"

uv_triangle :: proc() -> [3]g.Textured_Vertex {
    return {
        {{-1, -1, 0.5}, 0xffffffff, {-0.25, 0}},
        {{1, -1, 0.5}, 0xff0000ff, {1.25, 0}},
        {{0, 1, 0.5}, 0xff00ff00, {0.5, 1}},
    }
}

textured_sampling_and_depth :: proc(test: ^testing.T) {
    registry: r.Registry
    defer r.close(&registry)
    testing.expect(test, r.reset(&registry, 820, w.texturedProtocol))
    testing.expect(test, t.configure(820))
    t.begin(0)
    depth := g.depth(320, 180)
    projection := g.identity()
    projection[10], projection[11], projection[15] = 0.5, 1, 0
    view := g.camera({
        view_projection = projection,
        ambient         = 1,
        fog_color       = 0xff000000,
        fog_start       = 1,
        fog_end         = 2,
    })
    texture := gfx.texture({.RGBA8, 1, 4})
    pixels := data.pixels(.RGBA8, 1, 4)
    defer data.free_pixels(&pixels)
    rows := [4]u32{0xff0000ff, 0xff00ff00, 0xffff0000, 0xffffffff}
    for color, i in rows { r.put32(pixels.bytes, i * 4, color) }
    gfx.upload(texture, {0, 0, 1, 4}, pixels)
    material := g.material(texture)
    repeat := g.material(texture, {.Clamp, .Repeat})
    vertices := [3]g.Textured_Vertex {
        {{-1, -1, 1}, 0xffffffff, {0, 0}},
        {{2, -2, 2}, 0xffffffff, {0, 0}},
        {{0, 4, 4}, 0xffffffff, {0, 1.2}},
    }
    indices := [3]u32{0, 1, 2}
    mesh := g.textured_mesh(vertices[:], indices[:])
    for &vertex in vertices { vertex.uv = {0, -0.3} }
    wrapped := g.textured_mesh(vertices[:], indices[:])
    for &vertex in vertices {
        vertex.position[0] *= 2
        vertex.uv = {0, 1.3}
    }
    clipped := g.textured_mesh(vertices[:], indices[:])
    horizontal := gfx.texture({.RGBA8, 2, 1})
    horizontal_pixels := data.pixels(.RGBA8, 2, 1)
    defer data.free_pixels(&horizontal_pixels)
    r.put32(horizontal_pixels.bytes, 0, 0xff0000ff)
    r.put32(horizontal_pixels.bytes, 4, 0xffffffff)
    gfx.upload(horizontal, {0, 0, 2, 1}, horizontal_pixels)
    horizontal_clamp := g.material(horizontal)
    horizontal_repeat := g.material(horizontal, {.Repeat, .Clamp})
    for &vertex in vertices {
        vertex.uv = {-0.25, 12}
        vertex.color = 0xff80ffff
    }
    tinted := g.textured_mesh(vertices[:], indices[:])
    dim := g.camera({
        view_projection = projection,
        ambient         = 0.5,
        fog_color       = 0xff000000,
        fog_start       = 1,
        fog_end         = 2,
    })
    fog := g.camera({
        view_projection = projection,
        ambient         = 1,
        fog_color       = 0xff000000,
        fog_start       = 0,
        fog_end         = 1,
    })
    flat_vertices := uv_triangle()
    flat := g.textured_mesh(flat_vertices[:], indices[:])
    colored := triangle(0.75, 0xff0000ff)
    ortho := camera()
    commit(test, &registry)
    // At the center, projected barycentrics are approximately 1/4,1/4,1/2.
    // Dividing UV by clip W gives V about 0.3, unlike affine V about 0.6.
    for scenario in 0 ..< 5 {
        t.begin_draw(0)
        pass := gfx.begin_pass(gfx.screen(), {clear = true, color = 0xff222222})
        g.bind(pass, depth, view)
        geometry := mesh if scenario == 0 else wrapped if scenario <= 2 else clipped
        surface := repeat if scenario == 2 || scenario == 4 else material
        g.draw_textured(pass, geometry, surface)
        // Equal-depth fragments must retain the first draw's sample.
        g.draw_textured(pass, clipped, material)
        gfx.end_pass(pass)
        gfx.present(gfx.screen())
        commit(test, &registry)
        expected := [5]u32{0xff00ff00, 0xff0000ff, 0xffff0000, 0xffffffff, 0xff00ff00}
        testing.expect_value(test, registry.output[90 * 320 + 160], expected[scenario])
    }
    for scenario in 0 ..< 4 {
        t.begin_draw(0)
        pass := gfx.begin_pass(gfx.screen(), {clear = true, color = 0xff222222})
        g.bind(pass, depth, dim if scenario == 2 else fog if scenario == 3 else view)
        g.draw_textured(pass, tinted, horizontal_clamp if scenario == 0 else horizontal_repeat)
        gfx.end_pass(pass)
        gfx.present(gfx.screen())
        commit(test, &registry)
        expected := [4]u32{0xff0000ff, 0xff80ffff, 0xff408080, 0xff408080}
        testing.expect_value(test, registry.output[90 * 320 + 160], expected[scenario])
    }
    // The reference draw must flush queued GPU work and suppress its preview.
    registry.rasterizer = test_device
    registry.smooth_pan, registry.pixel_snap = true, true
    device_resident, device_failure, device_calls = false, false, 0
    t.begin_draw(0)
    pass := gfx.begin_pass(gfx.screen(), {clear = true, color = 0xff222222})
    g.bind(pass, depth, ortho)
    g.draw(pass, colored)
    g.draw(pass, colored)
    g.draw_textured(pass, flat, material)
    gfx.end_pass(pass)
    gfx.present(gfx.screen())
    commit(test, &registry)
    testing.expect_value(test, device_calls, 1)
    testing.expect(test, !registry.preview_enabled)
    testing.expect(test, registry.output[90 * 320 + 160] != 0xff00ffff)
    registry.rasterizer = nil
    // A late invalid material binding rolls back both color and depth writes.
    old_hash := r.hash(&registry)
    old_pixel := registry.output[90 * 320 + 160]
    t.begin_draw(0)
    pass = gfx.begin_pass(gfx.screen(), {clear = true, color = 0xff000000})
    g.bind(pass, depth, view)
    g.draw_textured(pass, mesh, material)
    args := [8]u32{texture.id, 0, 0, 0, 0, 0, 0, 0}
    model_bytes: [w.modelBytes]u8
    g.matrix_bytes(g.identity(), model_bytes[:])
    t.emit(w.op_draw_textured_mesh, t.Handle(mesh), args[:], model_bytes[:])
    gfx.end_pass(pass)
    gfx.present(gfx.screen())
    commit(test, &registry, false)
    testing.expect_value(test, r.hash(&registry), old_hash)
    testing.expect_value(test, registry.output[90 * 320 + 160], old_pixel)
}

textured_resource_ownership :: proc(test: ^testing.T) {
    registry: r.Registry
    defer r.close(&registry)
    testing.expect(test, r.reset(&registry, 801, w.texturedProtocol))
    testing.expect(test, t.configure(801))
    t.begin(0)
    texture := gfx.texture({.RGBA8, 2, 2})
    vertices := uv_triangle()
    indices := [3]u32{0, 1, 2}
    mesh := g.textured_mesh(vertices[:], indices[:])
    material := g.material(texture, {.Repeat, .Clamp})
    vertices[0].uv[0] = 17
    indices[0] = 2
    commit(test, &registry)
    mesh_slot := registry.slots[(mesh.id & w.handleIndexMask) - 1]
    material_slot := registry.slots[(material.id & w.handleIndexMask) - 1]
    testing.expect_value(test, mesh_slot.kind, r.Kind.Textured_Mesh)
    testing.expect_value(test, len(mesh_slot.data), 84)
    testing.expect_value(test, r.f32le(mesh_slot.data, 16), f64(-0.25))
    testing.expect_value(test, r.u32le(mesh_slot.data, 72), u32(0))
    testing.expect_value(test, material_slot.kind, r.Kind.Material)
    testing.expect_value(test, material_slot.link, texture.id)
    testing.expect_value(test, r.u32le(material_slot.data, 4), u32(1))
    testing.expect_value(test, r.u32le(material_slot.data, 8), u32(0))
    testing.expect_value(test, registry.bytes, 16 + 84 + 32)
    // A material pins its texture even when both handles belong to this packet.
    bytes := registry.bytes
    t.begin(1)
    gfx.destroy(texture)
    commit(test, &registry, false)
    testing.expect_value(test, registry.bytes, bytes)
    testing.expect_value(test, registry.slots[0].kind, r.Kind.Texture)

    // Reconfigure the SDK to recover its deliberately invalid local generation.
    testing.expect(test, t.configure(802))
    testing.expect(test, r.reset(&registry, 802, w.texturedProtocol))
    t.begin(0)
    texture = gfx.texture({.RGBA8, 2, 2})
    material = g.material(texture)
    vertices = uv_triangle()
    indices = {0, 1, 2}
    mesh = g.textured_mesh(vertices[:], indices[:])
    commit(test, &registry)
    t.begin(1)
    g.destroy(material)
    g.destroy(mesh)
    gfx.destroy(texture)
    commit(test, &registry)
    testing.expect_value(test, registry.bytes, 0)
}

textured_creation_rejects_old_protocols_and_invalid_data :: proc(test: ^testing.T) {
    for protocol in ([3]u32{w.stableVersion, w.meshProtocol, w.texturedProtocol}) {
        registry: r.Registry
        testing.expect(test, r.reset(&registry, 811, protocol))
        testing.expect(test, t.configure(811))
        t.begin(0)
        texture := gfx.texture({.RGBA8, 1, 1})
        _ = g.material(texture)
        commit(test, &registry, protocol == w.texturedProtocol)
        if protocol != w.texturedProtocol { testing.expect_value(test, registry.bytes, 0) }
        r.close(&registry)
    }
    for scenario in 0 ..< 8 {
        registry: r.Registry
        testing.expect(test, r.reset(&registry, 812, w.texturedProtocol))
        testing.expect(test, t.configure(812))
        t.begin(0)
        texture := gfx.texture({.Index8 if scenario == 0 else .RGBA8, 1, 1})
        if scenario == 7 {
            target := gfx.target({.RGBA8, 1, 1, {}})
            args := [8]u32{target.id, 0, 0, 0, 0, 0, 0, 0}
            h := t.reserve(w.kindMaterial, 0)
            t.emit(w.op_create_material, h, args[:])
        } else if scenario <= 1 {
            args := [8]u32{texture.id, 2 if scenario == 1 else 0, 0, 0, 0, 0, 0, 0}
            h := t.reserve(w.kindMaterial, 0)
            t.emit(w.op_create_material, h, args[:])
        } else {
            vertices := uv_triangle()
            indices := [3]u32{0, 1, 2}
            switch scenario {
            case 2:
                vertices[0].uv[0] = transmute(f32)u32(0x7fc00000)
            case 3:
                vertices[0].uv[1] = f32(w.maxTextureCoordinate) + 1
            case 4:
                indices[1] = 3
            case 5:
                vertices[0].color = 0x00ffffff
            case 6:
                vertices[0].position[0] = transmute(f32)u32(0x7f800000)
            }
            _ = g.textured_mesh(vertices[:], indices[:])
        }
        commit(test, &registry, false)
        testing.expect_value(test, registry.bytes, 0)
        r.close(&registry)
    }
}

material_texture_edits_and_budget_rollback :: proc(test: ^testing.T) {
    registry: r.Registry
    defer r.close(&registry)
    testing.expect(test, r.reset(&registry, 820, w.texturedProtocol))
    testing.expect(test, t.configure(820))
    t.begin(0)
    texture := gfx.texture({.RGBA8, 1, 1})
    _ = g.material(texture)
    pixels := data.pixels(.RGBA8, 1, 1)
    defer data.free_pixels(&pixels)
    pixels.bytes[0] = 73
    pixels.bytes[3] = 255
    gfx.upload(texture, {0, 0, 1, 1}, pixels)
    commit(test, &registry)
    testing.expect_value(test, registry.slots[0].data[0], u8(73))
    t.begin(1)
    pixels.bytes[0] = 99
    gfx.upload(texture, {0, 0, 1, 1}, pixels)
    invalid := g.material(texture, {cast(g.Address_Mode)2, .Clamp})
    _ = invalid
    commit(test, &registry, false)
    testing.expect_value(test, registry.slots[0].data[0], u8(73))
    t.begin(2)
    _ = g.material(texture)
    commit(test, &registry, false, registry.bytes)
    testing.expect_value(test, registry.bytes, 36)
    testing.expect_value(test, registry.slots[0].data[0], u8(73))
    testing.expect(test, r.reset(&registry, 821, w.texturedProtocol))
    testing.expect_value(test, registry.bytes, 0)
}

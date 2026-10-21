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

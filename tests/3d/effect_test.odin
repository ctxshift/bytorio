package mesh_test

import w "../../runtime/odin/resource_protocol"
import r "../../runtime/odin/resources"
import data "../../sdk/odin/data"
import gfx "../../sdk/odin/gfx"
import g "../../sdk/odin/gfx3d"
import t "../../sdk/odin/resource"
import "core:testing"

effect_blending_depth_and_rollback :: proc(test: ^testing.T) {
    defer r.software_close()
    for quality in ([3]int{0, 2, 6}) {
        registry: r.Registry
        defer r.close(&registry)
        testing.expect(test, r.reset(&registry, 930, w.effectProtocol))
        testing.expect(test, t.configure(930))
        if quality != 0 {
            r.software_configure(quality)
            registry.rasterizer = r.software_raster
        }
        t.begin(0)
        depth := g.depth(320, 180)
        view := camera()
        texture := gfx.texture({.RGBA8, 1, 1})
        pixels := data.pixels(.RGBA8, 1, 1)
        defer data.free_pixels(&pixels)
        r.put32(pixels.bytes, 0, 0x80000080)
        gfx.upload(texture, {0, 0, 1, 1}, pixels)
        alpha := g.effect_material(texture)
        additive := g.effect_material(texture, {blend = .Additive, depth_test = true})
        no_test := g.effect_material(texture, {depth_test = false})
        write := g.effect_material(texture, {depth_test = true, depth_write = true})
        vertices := [3]g.Textured_Vertex {
            {{-0.8, -0.8, 0.25}, 0xffffffff, {0, 0}},
            {{0, 0.8, 0.25}, 0xffffffff, {0, 0}},
            {{0.8, -0.8, 0.25}, 0xffffffff, {0, 0}},
        }
        indices := [3]u32{0, 1, 2}
        effect := g.textured_mesh(vertices[:], indices[:])
        for &vertex in vertices { vertex.position[2] = 1 }
        far_effect := g.textured_mesh(vertices[:], indices[:])
        front := triangle(0.1, 0xff00ff00)
        behind := triangle(0.5, 0xff00ff00)
        commit(test, &registry)
        expected := [7]u32 {
            0xff7f0080,
            0xffff0080,
            0xff00ff00,
            0xff007f80,
            0xff00ff00,
            0xff7f0080,
            0xff7f0080,
        }
        for scenario in 0 ..< len(expected) {
            t.begin_draw(0)
            pass := gfx.begin_pass(gfx.screen(), {clear = true, color = 0xffff0000})
            g.bind(pass, depth, view)
            if scenario == 2 || scenario == 3 { g.draw(pass, front) }
            surface :=
                additive if scenario == 1 else no_test if scenario == 3 || scenario == 6 else write if scenario == 5 else alpha
            g.draw_textured(pass, far_effect if scenario == 6 else effect, surface)
            if scenario == 4 || scenario == 5 { g.draw(pass, behind) }
            gfx.end_pass(pass)
            gfx.present(gfx.screen())
            commit(test, &registry)
            testing.expect_value(test, registry.output[90 * 320 + 160], expected[scenario])
        }
        old_hash := r.hash(&registry)
        t.begin(1)
        args := [8]u32{texture.id, 0, 0, 2, 1, 0, 0, 0}
        invalid := t.reserve(w.kindMaterial, 0)
        t.emit(w.op_create_effect_material, invalid, args[:])
        commit(test, &registry, false)
        testing.expect_value(test, r.hash(&registry), old_hash)
        testing.expect(test, r.reset(&registry, 931, w.alphaProtocol))
        testing.expect(test, t.configure(931))
        t.begin(0)
        texture = gfx.texture({.RGBA8, 1, 1})
        _ = g.effect_material(texture)
        commit(test, &registry, false)
        testing.expect_value(test, registry.bytes, 0)
    }
}

package mesh_test

import w "../../runtime/odin/resource_protocol"
import r "../../runtime/odin/resources"
import data "../../sdk/odin/data"
import gfx "../../sdk/odin/gfx"
import g "../../sdk/odin/gfx3d"
import t "../../sdk/odin/resource"
import "core:math"
import "core:testing"

billboard_pivots_and_axes :: proc(test: ^testing.T) {
    desc := g.Billboard_Desc {
        position = {3, 4, 5},
        size     = {2, 6},
        pivot    = {0.5, 1},
        view     = g.identity(),
    }
    model := g.billboard_model(desc)
    testing.expect_value(test, model[0], f32(2))
    testing.expect_value(test, model[5], f32(6))
    testing.expect_value(test, model[12], f32(2))
    testing.expect_value(test, model[13], f32(-2))
    testing.expect_value(test, model[14], f32(5))
    desc.rotation = math.PI / 2
    model = g.billboard_model(desc)
    testing.expect(test, abs(model[0]) < 0.0001)
    testing.expect(test, abs(model[1] - 2) < 0.0001)
    testing.expect(test, abs(model[4] + 6) < 0.0001)
    testing.expect(test, abs(model[12] - 9) < 0.0001)
    testing.expect(test, abs(model[13] - 3) < 0.0001)
    desc.view = g.look_at({4, 3, -4}, {0, 0, 0})
    desc.rotation = 0
    facing := g.billboard_model(desc)
    testing.expect(test, abs(facing[6]) > 0.1)
    desc.mode = .Upright
    upright := g.billboard_model(desc)
    testing.expect_value(test, upright[4], f32(0))
    testing.expect_value(test, upright[5], f32(6))
    testing.expect_value(test, upright[6], f32(0))
    for axis in 0 ..< 3 {
        anchor := upright[12 + axis] + upright[axis] * 0.5 + upright[4 + axis]
        testing.expect(test, abs(f64(anchor) - desc.position[axis]) < 0.0001)
    }
}

cutout_invalid_descriptors_roll_back :: proc(test: ^testing.T) {
    for scenario in 0 ..< 4 {
        registry: r.Registry
        testing.expect(test, r.reset(&registry, 840 + u32(scenario), w.alphaProtocol))
        testing.expect(test, t.configure(840 + u32(scenario)))
        t.begin(0)
        texture := gfx.texture({.RGBA8, 1, 1})
        pixels := data.pixels(.RGBA8, 1, 1)
        pixels.bytes[1], pixels.bytes[3] = 255, 255
        gfx.upload(texture, {0, 0, 1, 1}, pixels)
        commit(test, &registry)
        previous_hash, previous_version := r.hash(&registry), registry.slots[0].gpu_version
        t.begin(1)
        pixels.bytes[1] = 128
        gfx.upload(texture, {0, 0, 1, 1}, pixels)
        args := [8]u32{texture.id, 0, 0, 128, 0, 0, 0, 0}
        switch scenario {
        case 0:
            args[3] = w.maxAlphaCutoff + 1
        case 1:
            args[4] = 1
        case 2:
            args[0] = 0
        case 3:
            args[0] = gfx.texture({.Index8, 1, 1}).id
        }
        handle := t.reserve(w.kindMaterial, 0)
        t.emit(w.op_create_cutout_material, handle, args[:])
        commit(test, &registry, false)
        testing.expect_value(test, r.hash(&registry), previous_hash)
        testing.expect_value(test, registry.bytes, 4)
        testing.expect_value(test, registry.slots[0].gpu_version, previous_version)
        data.free_pixels(&pixels)
        r.close(&registry)
    }
}

cutout_color_and_depth_holes :: proc(test: ^testing.T) {
    for quality in ([3]int{1, 2, 6}) {
        registry: r.Registry
        testing.expect(test, r.reset(&registry, 830, w.alphaProtocol))
        testing.expect(test, t.configure(830))
        t.begin(0)
        depth := g.depth(320, 180)
        view := camera()
        texture := gfx.texture({.RGBA8, 2, 2})
        pixels := data.pixels(.RGBA8, 2, 2)
        for alpha, i in ([4]u8{0, 127, 128, 255}) {
            pixels.bytes[i * 4 + 1], pixels.bytes[i * 4 + 3] = alpha, alpha
        }
        gfx.upload(texture, {0, 0, 2, 2}, pixels)
        data.free_pixels(&pixels)
        materials := [5]g.Material {
            g.cutout_material(texture, 128),
            g.cutout_material(texture, 127),
            g.cutout_material(texture, 0),
            g.cutout_material(texture, 255),
            g.cutout_material(texture, 128),
        }
        quad := g.billboard()
        far_vertices := [4]g.Vertex {
            {{-1, -1, 0.75}, 0xffff0000},
            {{1, -1, 0.75}, 0xffff0000},
            {{1, 1, 0.75}, 0xffff0000},
            {{-1, 1, 0.75}, 0xffff0000},
        }
        indices := [6]u32{0, 2, 1, 0, 3, 2}
        far := g.mesh(far_vertices[:], indices[:])
        commit(test, &registry)
        if quality > 1 { registry.rasterizer = r.software_raster }
        r.software_configure(quality)
        for material, scenario in materials {
            t.begin_draw(0)
            pass := gfx.begin_pass(gfx.screen(), {clear = true, color = 0xff222222})
            g.bind(pass, depth, view)
            left := f64(-2) if scenario == 4 else f64(-1)
            g.draw_billboard(
                pass,
                quad,
                material,
                {position = {left, -1, 0.25}, size = {2, 2}, view = g.identity()},
            )
            // A later far draw must fill holes without covering surviving texels.
            g.draw(pass, far)
            gfx.end_pass(pass)
            gfx.present(gfx.screen())
            commit(test, &registry)
            expected := [5][4]u32 {
                {0xffff0000, 0xffff0000, 0xff00ff00, 0xff00ff00},
                {0xffff0000, 0xff00ff00, 0xff00ff00, 0xff00ff00},
                {0xff000000, 0xff00ff00, 0xff00ff00, 0xff00ff00},
                {0xffff0000, 0xffff0000, 0xffff0000, 0xff00ff00},
                {0xffff0000, 0xffff0000, 0xff00ff00, 0xffff0000},
            }
            for point, i in ([4][2]int{{80, 45}, {240, 45}, {80, 135}, {240, 135}}) {
                at := point[1] * 320 + point[0]
                testing.expect_value(test, registry.output[at], expected[scenario][i])
                expected_depth := f64(0.75) if expected[scenario][i] == 0xffff0000 else f64(0.25)
                slot := registry.slots[(depth.id & w.handleIndexMask) - 1]
                testing.expect_value(test, r.f32le(slot.data, at * 4), expected_depth)
            }
        }
        r.close(&registry)
        r.software_close()
    }
    // Older profiles reject alpha commands before publishing any resources.
    for protocol in ([2]u32{w.meshProtocol, w.texturedProtocol}) {
        registry: r.Registry
        testing.expect(test, r.reset(&registry, 831, protocol))
        testing.expect(test, t.configure(831))
        t.begin(0)
        texture := gfx.texture({.RGBA8, 1, 1})
        _ = g.cutout_material(texture)
        commit(test, &registry, false)
        testing.expect_value(test, registry.bytes, 0)
        r.close(&registry)
    }
}

package mesh_test

import w "../../runtime/odin/resource_protocol"
import r "../../runtime/odin/resources"
import gfx "../../sdk/odin/gfx"
import g "../../sdk/odin/gfx3d"
import t "../../sdk/odin/resource"
import "core:testing"

// This device deliberately withholds CPU writes until synchronization. Tests
// therefore detect missing barriers independently from the hardware backends.
sequence_color, sequence_depth: [320 * 180 * 4]u8
sequence_uploads, sequence_readbacks, sequence_draws: int
sequence_fail: bool
sequence_fail_sync: bool

sequence_device :: proc(job: r.Raster_Job) -> bool {
    if !job.continuation {
        copy(sequence_color[:], job.color)
        copy(sequence_depth[:], job.depth)
        sequence_uploads += 1
    }
    if len(job.vertices) != 0 {
        draw := job
        draw.color, draw.depth = sequence_color[:], sequence_depth[:]
        if !r.software_raster(draw) { return false }
        sequence_draws += 1
    }
    if sequence_fail || (sequence_fail_sync && !job.defer_readback) { return false }
    if !job.defer_readback {
        copy(job.color, sequence_color[:])
        copy(job.depth, sequence_depth[:])
        sequence_readbacks += 1
    }
    return true
}

resident_attachment_sequences :: proc(test: ^testing.T) {
    registry: r.Registry
    defer r.close(&registry)
    defer r.software_close()
    testing.expect(test, r.reset(&registry, 925))
    testing.expect(test, t.configure(925))
    t.begin(0)
    depth := g.depth(320, 180)
    view := camera()
    near := triangle(0.25, 0xff0000ff)
    far := triangle(0.75, 0xffff0000)
    offscreen := gfx.target({format = .RGBA8, width = 320, height = 180})
    commit(test, &registry)
    registry.rasterizer = sequence_device
    registry.deferred_raster = true
    sequence_uploads, sequence_readbacks, sequence_draws = 0, 0, 0
    sequence_fail, sequence_fail_sync = false, false

    t.begin_draw(0)
    pass := gfx.begin_pass(gfx.screen(), {clear = true, color = 0xff222222})
    g.bind(pass, depth, view)
    g.draw(pass, near)
    gfx.end_pass(pass)
    pass = gfx.begin_pass(gfx.screen())
    g.bind(pass, depth, view, clear = false)
    g.draw(pass, far)
    gfx.end_pass(pass)
    gfx.present(gfx.screen())
    commit(test, &registry)
    testing.expect_value(test, sequence_uploads, 1)
    testing.expect_value(test, sequence_readbacks, 1)
    testing.expect_value(test, sequence_draws, 2)
    testing.expect_value(test, registry.output[90 * 320 + 160], u32(0xff0000ff))
    testing.expect_value(
        test,
        r.f32le(registry.slots[(depth.id & w.handleIndexMask) - 1].data, (90 * 320 + 160) * 4),
        0.25,
    )

    // CPU HUD observes the earlier draw; later 3D loads its modified color and
    // the unchanged depth, so the farther triangle cannot overwrite the HUD.
    t.begin_draw(0)
    pass = gfx.begin_pass(gfx.screen(), {clear = true, color = 0xff222222})
    g.bind(pass, depth, view)
    g.draw(pass, near)
    gfx.rect(pass, 159, 89, 2, 2, 0xff00ff00)
    g.draw(pass, far)
    gfx.end_pass(pass)
    gfx.present(gfx.screen())
    commit(test, &registry)
    testing.expect_value(test, sequence_uploads, 3)
    testing.expect_value(test, sequence_readbacks, 3)
    testing.expect_value(test, registry.output[90 * 320 + 160], u32(0xff00ff00))

    // A clear starts a fresh sequence, rather than resurrecting old samples.
    t.begin_draw(0)
    pass = gfx.begin_pass(gfx.screen(), {clear = true, color = 0xff222222})
    g.bind(pass, depth, view)
    g.draw(pass, near)
    gfx.end_pass(pass)
    pass = gfx.begin_pass(gfx.screen(), {clear = true, color = 0xff222222})
    g.bind(pass, depth, view)
    g.draw(pass, far)
    gfx.end_pass(pass)
    gfx.present(gfx.screen())
    commit(test, &registry)
    testing.expect_value(test, sequence_uploads, 5)
    testing.expect_value(test, sequence_readbacks, 5)
    testing.expect_value(test, registry.output[90 * 320 + 160], u32(0xffff0000))

    // Switching targets and explicit readback both synchronize private output.
    t.begin_draw(0)
    pass = gfx.begin_pass(offscreen, {clear = true, color = 0xff222222})
    g.bind(pass, depth, view)
    g.draw(pass, near)
    gfx.end_pass(pass)
    read := gfx.readback(offscreen, {159, 89, 2, 2})
    pass = gfx.begin_pass(gfx.screen(), {clear = true, color = 0xff222222})
    g.bind(pass, depth, view)
    g.draw(pass, far)
    gfx.end_pass(pass)
    gfx.present(offscreen)
    commit(test, &registry)
    testing.expect_value(test, registry.output[90 * 320 + 160], u32(0xff0000ff))
    testing.expect_value(
        test,
        r.u32le(registry.slots[(read.id & w.handleIndexMask) - 1].data, 0),
        u32(0xff0000ff),
    )
    testing.expect_value(test, sequence_uploads, 7)
    testing.expect_value(test, sequence_readbacks, 7)

    previous := r.hash(&registry)
    // Rejection after a submitted private batch must preserve all public bytes.
    t.begin_draw(0)
    pass = gfx.begin_pass(gfx.screen(), {clear = true, color = 0xff222222})
    g.bind(pass, depth, view)
    g.draw(pass, near)
    gfx.end_pass(pass)
    pass = gfx.begin_pass(gfx.screen())
    g.bind(pass, depth, view, clear = false)
    stale := near
    stale.id += 1 << w.handleIndexBits
    model_bytes: [w.modelBytes]u8
    g.matrix_bytes(g.identity(), model_bytes[:])
    args: [8]u32
    t.emit(w.op_draw_mesh, t.Handle(stale), args[:], model_bytes[:])
    gfx.end_pass(pass)
    gfx.present(gfx.screen())
    commit(test, &registry, false)
    testing.expect_value(test, r.hash(&registry), previous)
    // The next fresh sequence overwrites abandoned scratch, including after a
    // late synchronization/device failure rather than an early draw failure.
    sequence_fail_sync = true
    t.begin_draw(0)
    pass = gfx.begin_pass(gfx.screen(), {clear = true, color = 0xff222222})
    g.bind(pass, depth, view)
    g.draw(pass, near)
    gfx.end_pass(pass)
    gfx.present(gfx.screen())
    commit(test, &registry, false)
    testing.expect_value(test, r.hash(&registry), previous)
    sequence_fail_sync = false
    sequence_fail = true
    t.begin_draw(0)
    pass = gfx.begin_pass(gfx.screen(), {clear = true, color = 0xff222222})
    g.bind(pass, depth, view)
    g.draw(pass, near)
    gfx.end_pass(pass)
    gfx.present(gfx.screen())
    commit(test, &registry, false)
    testing.expect_value(test, r.hash(&registry), previous)
    // Reset preserves the host opt-in, but the next transaction starts fresh.
    testing.expect(test, r.reset(&registry, 926))
    testing.expect(test, registry.deferred_raster)
}

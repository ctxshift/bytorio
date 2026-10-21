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
sequence_software: bool
sequence_private: bool

sequence_device :: proc(job: r.Raster_Job) -> bool {
    if sequence_software {
        if !job.continuation { sequence_uploads += 1 }
        if len(job.vertices) != 0 { sequence_draws += 1 }
        if !job.defer_readback { sequence_readbacks += 1 }
        if sequence_fail || (sequence_fail_sync && !job.defer_readback) { return false }
        center := (job.height / 2 * job.width + job.width / 2) * 4
        before := r.u32le(job.color, center)
        accepted := r.software_raster(job)
        if job.defer_readback {
            sequence_private = sequence_private && r.u32le(job.color, center) == before
        }
        return accepted
    }
    if !job.continuation {
        copy(sequence_color[:], job.color)
        copy(sequence_depth[:], job.depth)
        sequence_uploads += 1
    }
    if len(job.vertices) != 0 {
        draw := job
        draw.color, draw.depth = sequence_color[:], sequence_depth[:]
        draw.continuation, draw.defer_readback = false, false
        if !r.software_raster(draw) { return false }
        sequence_draws += 1
    }
    if sequence_fail || (sequence_fail_sync && !job.defer_readback) { return false }
    if !job.defer_readback {
        r.copy_raster_output(
            job.color,
            job.depth,
            job.border,
            job.mask,
            sequence_color[:],
            sequence_depth[:],
            job.width,
            job.height,
            0,
        )
        sequence_readbacks += 1
    }
    return true
}

resident_attachment_sequences :: proc(test: ^testing.T) {
    sequence_software = false
    attachment_sequences(test)
}

software_attachment_sequences :: proc(test: ^testing.T) {
    sequence_software = true
    sequence_private = true
    defer sequence_software = false
    r.software_configure(2)
    defer r.software_configure(0)
    attachment_sequences(test)
    testing.expect(
        test,
        sequence_private,
        "Deferred CPU batches must keep output private until synchronization",
    )
}

attachment_sequences :: proc(test: ^testing.T) {
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
    if sequence_software {
        counts := r.software_statistics()
        testing.expect_value(test, counts[0], u64(320 * 180 * 4 * 8))
        testing.expect_value(test, counts[1], u64(320 * 180 * 8))
        testing.expect_value(test, counts[2], u64(2))
        testing.expect_value(test, counts[3], u64(1))
    }
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
    // Rejected packets do not advance the host sequence. Rewind this test's
    // transport so subsequent failure and recovery probes reach the device.
    t.sequence = registry.sequence
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
    t.sequence = registry.sequence
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
    t.sequence = registry.sequence
    sequence_fail = false
    t.begin_draw(0)
    pass = gfx.begin_pass(gfx.screen(), {clear = true, color = 0xff222222})
    g.bind(pass, depth, view)
    g.draw(pass, far)
    gfx.end_pass(pass)
    gfx.present(gfx.screen())
    commit(test, &registry)
    testing.expect_value(test, registry.output[90 * 320 + 160], u32(0xffff0000))
    // Reset preserves the host opt-in, but the next transaction starts fresh.
    testing.expect(test, r.reset(&registry, 926))
    testing.expect(test, registry.deferred_raster)
}

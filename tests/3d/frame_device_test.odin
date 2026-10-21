package mesh_test

import w "../../runtime/odin/resource_protocol"
import r "../../runtime/odin/resources"
import gfx "../../sdk/odin/gfx"
import g "../../sdk/odin/gfx3d"
import t "../../sdk/odin/resource"
import "core:testing"

frame_colors, frame_depths: [2][320 * 180 * 4]u8
frame_versions: [2]u64
published_index, frame_reads, frame_publishes: int
frame_fail_stage, frame_fail_publish, frame_fail_read: bool

snapshot_device :: proc(job: r.Frame_Job) -> bool {
    candidate := 1 - published_index
    switch job.action {
    case .Invalidate:
        frame_versions = {}
        return true
    case .Stage:
        if frame_fail_stage { return false }
        copy(frame_colors[candidate][:], sequence_color[:])
        copy(frame_depths[candidate][:], sequence_depth[:])
        frame_versions[candidate] = job.version
        return true
    case .Publish:
        if frame_fail_publish || frame_versions[candidate] != job.version { return false }
        published_index = candidate
        frame_publishes += 1
        return true
    case .Read:
        if frame_fail_read || frame_versions[published_index] != job.version { return false }
        frame_reads += 1
        r.copy_raster_output(
            job.color,
            job.depth,
            job.preview,
            job.mask,
            frame_colors[published_index][:],
            frame_depths[published_index][:],
            job.width,
            job.height,
            0,
        )
        return true
    }
    return false
}

committed_frame_transactions :: proc(test: ^testing.T) {
    registry: r.Registry
    defer r.close(&registry)
    defer r.software_close()
    testing.expect(test, r.reset(&registry, 935))
    testing.expect(test, t.configure(935))
    t.begin(0)
    depth := g.depth(320, 180)
    view := camera()
    near := triangle(0.25, 0xff0000ff)
    far := triangle(0.75, 0xffff0000)
    commit(test, &registry)
    registry.rasterizer = sequence_device
    registry.frame_device = snapshot_device
    registry.deferred_raster = true
    frame_reads, frame_publishes, published_index = 0, 0, 0
    frame_fail_stage, frame_fail_publish, frame_fail_read = false, false, false
    sequence_fail, sequence_fail_sync = false, false
    sequence_uploads, sequence_readbacks, sequence_draws = 0, 0, 0
    // Opaque HUD is independent of the unresolved world. Two frames overwrite
    // their color/depth pair without materializing the previous committed frame.
    for mesh in ([2]g.Mesh{near, far}) {
        t.begin_draw(0)
        pass := gfx.begin_pass(gfx.screen(), {clear = true, color = 0xff222222})
        g.bind(pass, depth, view)
        g.draw(pass, mesh)
        gfx.rect(pass, 159, 89, 2, 2, 0xff00ff00)
        gfx.end_pass(pass)
        gfx.present(gfx.screen())
        commit(test, &registry)
        testing.expect(test, registry.gpu_lazy)
        testing.expect_value(test, registry.gpu_frame.job.version, frame_versions[published_index])
        testing.expect_value(
            test,
            r.u32le(registry.screen.data, (90 * 320 + 160) * 4),
            u32(0xff00ff00),
        )
        testing.expect_value(test, frame_reads, 0)
        testing.expect_value(test, sequence_readbacks, 0)
    }
    testing.expect_value(test, frame_publishes, 2)
    previous := registry.gpu_frame.job.version
    // Fail at staging and again at the publication seam; neither may replace
    // the committed image, despite overwriting the private raster scratch.
    for publish_failure in ([2]bool{false, true}) {
        frame_fail_stage, frame_fail_publish = !publish_failure, publish_failure
        t.begin_draw(0)
        pass := gfx.begin_pass(gfx.screen(), {clear = true, color = 0xff222222})
        g.bind(pass, depth, view)
        g.draw(pass, near)
        gfx.end_pass(pass)
        gfx.present(gfx.screen())
        commit(test, &registry, false)
        // Retry after rejection with the host's unchanged sequence number.
        t.sequence = registry.sequence
        testing.expect_value(test, registry.gpu_frame.job.version, previous)
        testing.expect_value(test, frame_versions[published_index], previous)
        testing.expect(test, registry.gpu_lazy)
        testing.expect_value(test, frame_publishes, 2)
    }
    frame_fail_stage, frame_fail_publish = false, false
    // A command rejected after presentation must not expose its private frame.
    t.begin_draw(0)
    rejected := gfx.begin_pass(gfx.screen(), {clear = true, color = 0xff222222})
    g.bind(rejected, depth, view)
    g.draw(rejected, near)
    gfx.end_pass(rejected)
    gfx.present(gfx.screen())
    invalid_args: [8]u32
    t.emit(w.op_rect, {}, invalid_args[:], nil)
    commit(test, &registry, false)
    t.sequence = registry.sequence
    testing.expect_value(test, frame_versions[published_index], previous)
    testing.expect(test, registry.gpu_lazy)
    frame_fail_read = true
    testing.expect(test, !r.materialize(&registry))
    testing.expect(test, registry.gpu_lazy)
    frame_fail_read = false
    testing.expect(test, r.materialize(&registry))
    testing.expect_value(test, frame_reads, 1)
    testing.expect_value(test, registry.output[90 * 320 + 160], u32(0xff00ff00))
    testing.expect_value(test, registry.output[95 * 320 + 160], u32(0xffff0000))
    testing.expect_value(
        test,
        r.f32le(registry.slots[(depth.id & w.handleIndexMask) - 1].data, (90 * 320 + 160) * 4),
        0.75,
    )
    // A consumer materializes once; repeated logical reads do not transfer again.
    testing.expect(test, r.materialize(&registry))
    testing.expect_value(test, frame_reads, 1)
    // Loading a committed attachment requires its CPU truth before copy-on-write.
    t.begin_draw(0)
    pass := gfx.begin_pass(gfx.screen())
    g.bind(pass, depth, view, clear = false)
    g.draw(pass, near)
    gfx.end_pass(pass)
    gfx.present(gfx.screen())
    commit(test, &registry)
    testing.expect(test, registry.gpu_lazy)
    t.begin(1)
    g.destroy(depth)
    commit(test, &registry)
    testing.expect(test, !registry.gpu_lazy)
    testing.expect_value(test, registry.output[95 * 320 + 160], u32(0xff0000ff))
    testing.expect_value(test, frame_reads, 2)
    testing.expect(test, r.reset(&registry, 936))
    testing.expect_value(test, registry.gpu_frame.job.version, u64(0))
    testing.expect(test, registry.frame_device != nil)
    committed_frame_barriers(test, &registry)
}

committed_frame_barriers :: proc(test: ^testing.T, registry: ^r.Registry) {
    testing.expect(test, t.configure(936))
    t.begin(0)
    depth := g.depth(320, 180)
    view := camera()
    near := triangle(0.25, 0xff0000ff)
    far := triangle(0.75, 0xffff0000)
    offscreen := gfx.target({format = .RGBA8, width = 320, height = 180})
    commit(test, registry)
    // A HUD followed by more 3D must become an ordinary color/depth barrier.
    t.begin_draw(0)
    pass := gfx.begin_pass(gfx.screen(), {clear = true, color = 0xff222222})
    g.bind(pass, depth, view)
    g.draw(pass, near)
    gfx.rect(pass, 159, 89, 2, 2, 0xff00ff00)
    g.draw(pass, far)
    gfx.end_pass(pass)
    gfx.present(gfx.screen())
    commit(test, registry)
    testing.expect(test, registry.gpu_lazy)
    testing.expect(test, r.materialize(registry))
    testing.expect_value(test, registry.output[90 * 320 + 160], u32(0xff00ff00))
    testing.expect_value(test, registry.output[95 * 320 + 160], u32(0xff0000ff))
    // Partial-alpha replacement cannot remain in the opaque HUD layer.
    t.begin_draw(0)
    pass = gfx.begin_pass(gfx.screen(), {clear = true, color = 0xff222222})
    g.bind(pass, depth, view)
    g.draw(pass, near)
    gfx.rect(pass, 159, 89, 2, 2, 0xff00ff00)
    gfx.rect(pass, 159, 89, 2, 2, 0x80000080)
    gfx.end_pass(pass)
    gfx.present(gfx.screen())
    commit(test, registry)
    testing.expect(test, !registry.gpu_lazy)
    testing.expect_value(test, registry.gpu_frame.job.version, u64(0))
    testing.expect_value(test, registry.output[90 * 320 + 160], u32(0xff000080))
    // Offscreen final attachments can be published, and explicit readback in a
    // later draw materializes their resource backing before copying it.
    t.begin_draw(0)
    pass = gfx.begin_pass(offscreen, {clear = true, color = 0xff222222})
    g.bind(pass, depth, view)
    g.draw(pass, far)
    gfx.end_pass(pass)
    gfx.present(offscreen)
    commit(test, registry)
    testing.expect(test, registry.gpu_lazy)
    t.begin_draw(0)
    read := gfx.readback(offscreen, {160, 95, 1, 1})
    gfx.present(offscreen)
    commit(test, registry)
    testing.expect(test, !registry.gpu_lazy)
    testing.expect_value(test, registry.output[95 * 320 + 160], u32(0xffff0000))
    testing.expect_value(
        test,
        r.u32le(registry.slots[(read.id & w.handleIndexMask) - 1].data, 0),
        u32(0xffff0000),
    )
}

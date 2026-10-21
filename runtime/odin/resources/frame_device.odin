package resources

import w "../resource_protocol"
import "core:mem"

// Stage may fail without changing the published snapshot. Publish is an atomic
// host-side swap after all device work succeeds; no supplied pointer is retained.
Frame_Action :: enum u32 {
    Stage,
    Publish,
    Read,
    Invalidate,
}
Frame_Job :: struct {
    action:                      Frame_Action,
    version:                     u64,
    color, depth, preview, mask: []u8,
    width, height:               int,
}
Frame_Proc :: proc(job: Frame_Job) -> bool

copy_raster_output :: proc(
    color, depth, preview, mask, source_color, source_depth: []u8,
    width, height, border: int,
) {
    rw := width + border * 2
    for y in 0 ..< height {
        source := ((y + border) * rw + border) * 4
        if len(mask) == 0 {
            copy(color[y * width * 4:][:width * 4], source_color[source:][:width * 4])
        } else {
            for x in 0 ..< width {
                at := y * width + x
                if mask[at] == 0 { copy(color[at * 4:][:4], source_color[source + x * 4:][:4]) }
            }
        }
        copy(depth[y * width * 4:][:width * 4], source_depth[source:][:width * 4])
    }
    copy(preview, source_color)
}
Committed_Frame :: struct {
    job:                Frame_Job,
    color_id, depth_id: u32,
}

materialize :: proc(r: ^Registry) -> bool {
    if !r.gpu_lazy { return true }
    job := r.gpu_frame.job
    job.action = .Read
    if r.frame_device == nil || !r.frame_device(job) {
        return fail(r, "committed GPU snapshot read failed")
    }
    for at in 0 ..< len(r.output) {
        color := u32le(job.color, at * 4)
        r.output[at] = color if color >> 24 == 255 else over(color, r.preview_background)
    }
    r.gpu_lazy = false
    return true
}

ensure_cpu_slot :: proc(t: ^Transaction, slot: ^Slot) -> bool {
    r := t.registry
    if slot != nil &&
       r.gpu_lazy &&
       (raw_data(slot.data) == raw_data(r.gpu_frame.job.color) ||
               raw_data(slot.data) == raw_data(r.gpu_frame.job.depth)) {
        return materialize(r)
    }
    return true
}

read_image :: proc(t: ^Transaction, id: u32) -> ^Slot {
    slot := image(t, id)
    if !ensure_cpu_slot(t, slot) { return nil }
    return slot
}

frame_mask :: proc(t: ^Transaction, size: int) -> bool {
    if len(t.preview_mask) == size { return true }
    if len(t.preview_mask) != 0 { return false }
    pointer, error := mem.alloc(size, 1)
    if error != nil { return false }
    mem.zero(pointer, size)
    t.preview_mask = (cast([^]u8)pointer)[:size]
    return true
}

can_defer_command :: proc(t: ^Transaction, op: u32) -> bool {
    if raster_state_command(op) { return true }
    if t.registry.frame_device == nil { return false }
    if op == w.op_present { return true }
    return(
        (op == w.op_rect || op == w.op_text || op == w.op_sprite || op == w.op_draw) &&
        t.render.active &&
        t.render.target == 0 &&
        t.render.pipeline == default_pipeline(w.format_rgba8) \
    )
}

prepare_frame :: proc(t: ^Transaction) -> bool {
    r := t.registry
    if !t.gpu_present {
        if r.gpu_lazy {
            color := image(t, r.gpu_frame.color_id)
            depth := lookup(t, r.gpu_frame.depth_id, .Depth)
            changed :=
                t.draw_phase ||
                color == nil ||
                depth == nil ||
                raw_data(color.data) != raw_data(r.gpu_frame.job.color) ||
                raw_data(depth.data) != raw_data(r.gpu_frame.job.depth)
            if changed && !materialize(r) { return false }
        }
        return true
    }
    // A new snapshot may replace old device storage only after any surviving
    // resource bytes have been materialized. Fully overwritten pairs need no read.
    if r.gpu_lazy {
        old_color := image(t, r.gpu_frame.color_id)
        old_depth := lookup(t, r.gpu_frame.depth_id, .Depth)
        color_kept :=
            old_color != nil && raw_data(old_color.data) == raw_data(r.gpu_frame.job.color)
        depth_kept :=
            old_depth != nil && raw_data(old_depth.data) == raw_data(r.gpu_frame.job.depth)
        if (color_kept || depth_kept) && !materialize(r) { return false }
    }
    job := Frame_Job {
        action  = .Stage,
        version = mesh_version(r),
        color   = t.gpu_job.color,
        depth   = t.gpu_job.depth,
        preview = t.gpu_job.border,
        mask    = t.preview_mask if t.gpu_overlay else nil,
        width   = t.gpu_job.width,
        height  = t.gpu_job.height,
    }
    if !r.frame_device(
        job,
    ) { return fail(r, "GPU snapshot staging failed; transaction discarded") }
    t.gpu_frame = {job, t.gpu_target, t.gpu_depth}
    job.action = .Publish
    if !r.frame_device(
        job,
    ) { return fail(r, "GPU snapshot publication failed; transaction discarded") }
    return true
}

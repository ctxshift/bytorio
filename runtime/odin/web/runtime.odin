package main

import abi "../abi"
import cartridge "../cartridge"
import core "../core"
import presentation "../presentation"
import resources "../resources"
import "base:runtime"

resource_registry: resources.Registry
resource_packet: [resources.PACKET_BYTES]u8
resource_session: u32
presenter: presentation.State
@(export)
runtime_presentation :: proc "c" (width, height: u32) -> u32 {
    context = runtime.default_context()
    if runtime_materialize() == 0 { return 0 }
    pixels := presentation.prepare(
        &presenter,
        &resource_registry,
        int(min(width, 1920)),
        int(min(height, 1080)),
    )
    return u32(uintptr(raw_data(pixels)))
}
@(export)
runtime_presentation_width :: proc "c" () -> u32 { return u32(presenter.width) }
@(export)
runtime_presentation_height :: proc "c" () -> u32 { return u32(presenter.height) }
@(export)
runtime_presentation_active :: proc "c" () -> u32 { return u32(presenter.active) }
when #config(GPU_RASTER, false) {
    foreign import gpu "env"
    foreign gpu {
        stage_frame_gpu :: proc "c" (color, depth, preview, mask, width, height, low, high: u32) -> u32 ---
        read_frame_gpu :: proc "c" (color, depth, preview, mask, width, height, low, high: u32) -> u32 ---
        publish_frame_gpu :: proc "c" (low, high: u32) -> u32 ---
        invalidate_frame_gpu :: proc "c" () ---
        texture_gpu :: proc "c" (pixels, width, height, low, high, address_u, address_v, cutout, alpha_cutoff, effect, additive, skip_depth_test, skip_depth_write: u32) ---
        mesh_gpu :: proc "c" (low, high, data, vertices, indices, palette, model, view, light: u32, ambient: f32, textured: u32) ---
        raster_gpu :: proc "c" (vertices, count, color, depth, width, height: u32, x, y, w, h: i32, fog: u32, fog_start, fog_end: f32, border, continuation, defer_readback, mask: u32) -> u32 ---
    }
    gpu_frame :: proc(job: resources.Frame_Job) -> bool {
        low, high := u32(job.version), u32(job.version >> 32)
        switch job.action {
        case .Invalidate:
            invalidate_frame_gpu(); return true
        case .Publish:
            return publish_frame_gpu(low, high) == 1
        case .Stage, .Read:
            execute := stage_frame_gpu if job.action == .Stage else read_frame_gpu
            return(
                execute(
                    u32(uintptr(raw_data(job.color))),
                    u32(uintptr(raw_data(job.depth))),
                    u32(uintptr(raw_data(job.preview))),
                    u32(uintptr(raw_data(job.mask))),
                    u32(job.width),
                    u32(job.height),
                    low,
                    high,
                ) ==
                1 \
            )
        }
        return false
    }
    gpu_raster :: proc(job: resources.Raster_Job) -> bool {
        texture_gpu(
            u32(uintptr(raw_data(job.texture.pixels))),
            job.texture.width,
            job.texture.height,
            u32(job.texture.version),
            u32(job.texture.version >> 32),
            job.texture.address_u,
            job.texture.address_v,
            u32(job.texture.cutout),
            job.texture.alpha_cutoff,
            u32(job.texture.effect),
            u32(job.texture.additive),
            u32(job.texture.skip_depth_test),
            u32(job.texture.skip_depth_write),
        )
        for value in job.draws {
            draw := value
            mesh_gpu(
                u32(draw.version),
                u32(draw.version >> 32),
                u32(uintptr(raw_data(draw.data))),
                draw.vertex_count,
                draw.index_count,
                u32(uintptr(raw_data(draw.palette))),
                u32(uintptr(&draw.model[0])),
                u32(uintptr(&draw.view[0])),
                u32(uintptr(&draw.light[0])),
                draw.ambient,
                u32(draw.textured),
            )
        }
        return(
            raster_gpu(
                u32(uintptr(raw_data(job.vertices))),
                u32(len(job.vertices) / resources.raster_stride(job.texture)),
                u32(uintptr(raw_data(job.color))),
                u32(uintptr(raw_data(job.depth))),
                u32(job.width),
                u32(job.height),
                job.clip[0],
                job.clip[1],
                job.clip[2],
                job.clip[3],
                job.fog_color,
                job.fog_start,
                job.fog_end,
                u32(uintptr(raw_data(job.border))),
                u32(job.continuation),
                u32(job.defer_readback),
                u32(uintptr(raw_data(job.mask))),
            ) ==
            1 \
        )
    }
}
@(export)
runtime_cpu_bytes :: proc "c" () -> u32 { return u32(resources.software_storage_bytes()) }
@(export)
runtime_cpu_stat :: proc "c" (index: u32) -> u64 {
    if index >= 4 { return 0 }
    return resources.software_statistics()[index]
}
@(export)
runtime_cpu_configure :: proc "c" (quality, pixel_snap, smooth_pan: u32) -> u32 {
    context = runtime.default_context()
    if quality != 1 && quality != 2 && quality != 6 { return 0 }
    if !resources.materialize(&resource_registry) { return 0 }
    resources.apply_output(&resource_registry)
    if resource_registry.frame_device != nil {
        _ = resource_registry.frame_device({action = .Invalidate})
        resource_registry.gpu_frame = {}
    }
    resources.software_configure(int(quality))
    resource_registry.rasterizer =
        resources.software_raster if quality > 1 || pixel_snap != 0 || smooth_pan != 0 else nil
    resource_registry.pixel_snap = pixel_snap != 0 || smooth_pan != 0
    resource_registry.smooth_pan = smooth_pan != 0
    resource_registry.resident_meshes = false
    resource_registry.deferred_raster = resource_registry.rasterizer != nil
    resource_registry.frame_device = nil
    return 1
}
@(export)
runtime_gpu_configure :: proc "c" (pixel_snap, smooth_pan: u32, resident_meshes: u32) -> u32 {
    context = runtime.default_context()
    when #config(GPU_RASTER, false) {
        resource_registry.rasterizer = gpu_raster
        resource_registry.frame_device = gpu_frame
        resource_registry.deferred_raster = true
        resource_registry.pixel_snap = pixel_snap != 0
        resource_registry.smooth_pan = smooth_pan != 0
        resource_registry.resident_meshes = resident_meshes != 0
        return 1
    }
    return 0
}
@(export)
runtime_gpu_preview :: proc "c" () -> u32 {
    return(
        u32(uintptr(raw_data(resource_registry.preview))) if resource_registry.preview_enabled else 0 \
    )
}
@(export)
runtime_gpu_mask :: proc "c" () -> u32 {
    mask := raw_data(resource_registry.preview_mask)
    return u32(uintptr(mask))
}
@(export)
runtime_gpu_background :: proc "c" () -> u32 { return resource_registry.preview_background }
@(export)
runtime_gpu_dx :: proc "c" () -> f64 { return resource_registry.preview_residual[0] }
@(export)
runtime_gpu_dy :: proc "c" () -> f64 { return resource_registry.preview_residual[1] }
@(export)
runtime_logical_pixels :: proc "c" () -> u32 { return u32(uintptr(&core.pixels[0])) }
@(export)
runtime_gpu_version_low :: proc "c" () -> u32 {
    version := resource_registry.gpu_frame.job.version
    return u32(version)
}
@(export)
runtime_gpu_version_high :: proc "c" () -> u32 {
    version := resource_registry.gpu_frame.job.version
    return u32(version >> 32)
}
@(export)
runtime_materialize :: proc "c" () -> u32 {
    context = runtime.default_context()
    if !resources.materialize(&resource_registry) { return 0 }
    resources.apply_output(&resource_registry)
    return 1
}
@(export)
runtime_resource_close :: proc "c" () {
    context = runtime.default_context()
    resources.close(&resource_registry)
    resources.software_close()
    presentation.close(&presenter)
}
@(export)
runtime_resource_reset :: proc "c" (protocol: u32) -> u32 {
    context = runtime.default_context()
    if resource_session == max(u32) {

        return 0
    }
    resource_session += 1
    if !resources.reset(&resource_registry, resource_session, protocol if protocol != 0 else 2) {

        return 0
    }
    return resource_session
}
@(export)
runtime_resource_packet :: proc "c" () -> u32 {

    return u32(uintptr(&resource_packet))
}
@(export)
runtime_resource_capacity :: proc "c" () -> u32 {

    return resources.PACKET_BYTES
}
@(export)
runtime_resource_submit :: proc "c" (size: u32) -> u32 {
    context = runtime.default_context()
    if size > resources.PACKET_BYTES {

        resource_registry.error = "resource packet too large"
        return 0
    }
    return u32(
        resources.submit(
            &resource_registry,
            resource_packet[:size],
            display = u32(core.width << 16 | core.height),
        ),
    )
}
@(export)
runtime_resource_mailbox :: proc "c" () -> u32 {
    context = runtime.default_context()
    return u32(resources.mailbox(&resource_registry, resource_packet[:]))
}
@(export)
runtime_resource_error :: proc "c" () -> u32 {
    return u32(uintptr(raw_data(resource_registry.error)))
}
@(export)
runtime_resource_error_size :: proc "c" () -> u32 {

    return u32(len(resource_registry.error))
}
@(export)
runtime_resource_error_command :: proc "c" () -> i32 {

    return i32(resource_registry.command)
}
@(export)
runtime_resource_hash :: proc "c" () -> u32 {
    context = runtime.default_context()
    return resources.hash(&resource_registry)
}
@(export)
runtime_resource_bytes :: proc "c" () -> u32 {

    return u32(resource_registry.bytes)
}
@(export)
runtime_resource_stat :: proc "c" (index: u32) -> u64 {
    switch index {
    case 0:
        return resource_registry.stats.packet_bytes
    case 1:
        return resource_registry.stats.copy_bytes
    case 2:
        return resource_registry.stats.pixel_work
    case 3:
        return resource_registry.stats.peak_bytes
    case 4:
        return resource_registry.stats.triangles
    case 5:
        return resource_registry.stats.voxel_cells
    case 6:
        return resource_registry.stats.voxel_faces
    case 7:
        return resource_registry.stats.voxel_rebuilds
    case 8, 9, 10:
        storage := resources.mesh_storage(&resource_registry)
        return storage[index - 8]
    }
    return 0
}

cartridge_buffer: []u8
cartridge_info: cartridge.Cartridge
cartridge_error: string
@(export)
runtime_cartridge_buffer :: proc "c" () -> u32 {

    return u32(uintptr(raw_data(cartridge_buffer)))
}
@(export)
runtime_cartridge_reserve :: proc "c" (size: u32) -> u32 {
    context = runtime.default_context()
    context.allocator = runtime.default_wasm_allocator()
    cartridge_info = {}
    delete(cartridge_buffer)
    cartridge_buffer = nil
    if size == 0 || size > cartridge.MAX_BYTES {
        return 0
    }
    cartridge_buffer = make([]u8, int(size))
    return u32(uintptr(raw_data(cartridge_buffer)))
}
@(export)
runtime_cartridge_capacity :: proc "c" () -> u32 {

    return cartridge.MAX_BYTES
}
@(export)
runtime_cartridge_parse :: proc "c" (size: u32) -> u32 {
    context = runtime.default_context()
    cartridge_info = {}
    cartridge_error = "invalid PNG cartridge size"
    if size > u32(len(cartridge_buffer)) {

        return 0
    }
    cartridge_info, cartridge_error = cartridge.parse(cartridge_buffer[:size])
    return cartridge_info.language
}
@(export)
runtime_content_size :: proc "c" (id: u32) -> u32 {
    context = runtime.default_context()
    return u32(len(cartridge.content_blob(cartridge_info.content, id)))
}
@(export)
runtime_content_pointer :: proc "c" (id: u32) -> u32 {
    context = runtime.default_context()
    return u32(uintptr(raw_data(cartridge.content_blob(cartridge_info.content, id))))
}
@(export)
runtime_cartridge_code :: proc "c" () -> u32 {

    return u32(uintptr(raw_data(cartridge_info.code)))
}
@(export)
runtime_cartridge_code_size :: proc "c" () -> u32 {

    return u32(len(cartridge_info.code))
}
@(export)
runtime_cartridge_title :: proc "c" () -> u32 {
    return u32(uintptr(raw_data(cartridge_info.title)))
}
@(export)
runtime_cartridge_title_size :: proc "c" () -> u32 {

    return u32(len(cartridge_info.title))
}
@(export)
runtime_cartridge_profile :: proc "c" () -> u32 { return cartridge_info.profile }
@(export)
runtime_cartridge_sdk :: proc "c" () -> u32 { return cartridge_info.sdk }
@(export)
runtime_cartridge_abi :: proc "c" () -> u32 { return cartridge_info.abi_version }
@(export)
runtime_cartridge_display :: proc "c" () -> u32 {

    return cartridge_info.display
}
@(export)
runtime_cartridge_error :: proc "c" () -> u32 {

    return u32(uintptr(raw_data(cartridge_error)))
}
@(export)
runtime_cartridge_error_size :: proc "c" () -> u32 {

    return u32(len(cartridge_error))
}

frame: abi.Frame
commands: [abi.MAX_COMMANDS]abi.Command
batch: [abi.MAX_COMMANDS]abi.Draw_Command
text: [abi.MAX_TEXT_BYTES]u8
assets: [abi.MAX_GRAPHICS_BYTES]u8
@(export)
runtime_batch :: proc "c" () -> u32 {

    return u32(uintptr(&batch))
}
@(export)
runtime_text :: proc "c" () -> u32 {

    return u32(uintptr(&text))
}
@(export)
runtime_assets :: proc "c" () -> u32 {

    return u32(uintptr(&assets))
}
@(export)
runtime_load_graphics :: proc "c" (size: u32) -> u32 {
    context = runtime.default_context()
    if size > abi.MAX_GRAPHICS_BYTES {

        return 0
    }
    return u32(core.load_graphics(assets[:size]))
}
@(export)
runtime_render_batch :: proc "c" (count, size: u32) -> u32 {
    context = runtime.default_context()
    if count > abi.MAX_COMMANDS || size > abi.MAX_TEXT_BYTES {

        return 0
    }
    if !core.render_batch(batch[:count], text[:size]) {

        return 0
    }
    resources.apply_output(&resource_registry)
    return 1
}
@(export)
runtime_commands :: proc "c" () -> u32 {

    return u32(uintptr(&commands))
}
@(export)
runtime_render_commands :: proc "c" (count: u32) -> u32 {
    context = runtime.default_context()
    if count > abi.MAX_COMMANDS {

        return 0
    }
    if !core.render_commands(commands[:count]) {

        return 0
    }
    resources.apply_output(&resource_registry)
    return 1
}
@(export)
runtime_init :: proc "c" () {
    context = runtime.default_context()
    core.init()
}
@(export)
runtime_frame :: proc "c" () -> u32 {

    return u32(uintptr(&frame))
}
@(export)
runtime_pixels :: proc "c" () -> u32 {
    if runtime_materialize() == 0 { return 0 }

    return u32(uintptr(&core.pixels))
}
@(export)
runtime_sample :: proc "c" () -> u32 {

    return u32(uintptr(&core.sample))
}
@(export)
runtime_render :: proc "c" () -> u32 {
    context = runtime.default_context()
    return u32(core.render(frame))
}
@(export)
runtime_hash :: proc "c" () -> u32 {
    context = runtime.default_context()
    if runtime_materialize() == 0 { return 0 }
    return core.hash()
}

@(export)
runtime_display :: proc "c" (mode: u32) -> u32 {
    context = runtime.default_context()
    return u32(core.set_display(mode))
}

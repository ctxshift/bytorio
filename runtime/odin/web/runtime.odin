package main

import abi "../abi"
import cartridge "../cartridge"
import core "../core"
import resources "../resources"
import "base:runtime"

resource_registry: resources.Registry
resource_packet: [resources.PACKET_BYTES]u8
resource_session: u32
@(export)
runtime_resource_close :: proc "c" () {
    context = runtime.default_context()
    resources.close(&resource_registry)
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
        return resource_registry.stats.peak_bytes}
    return 0
}

cartridge_buffer: [cartridge.MAX_BYTES]u8
cartridge_info: cartridge.Cartridge
cartridge_error: string
@(export)
runtime_cartridge_buffer :: proc "c" () -> u32 {

    return u32(uintptr(&cartridge_buffer))
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
    if size > cartridge.MAX_BYTES {

        return 0
    }
    cartridge_info, cartridge_error = cartridge.parse(cartridge_buffer[:size])
    return cartridge_info.language
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
    return core.hash()
}

@(export)
runtime_display :: proc "c" (mode: u32) -> u32 {
    context = runtime.default_context()
    return u32(core.set_display(mode))
}

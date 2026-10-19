package main

import "base:runtime"
import abi "../abi"
import core "../core"

frame: abi.Frame
commands: [abi.MAX_COMMANDS]abi.Command
batch: [abi.MAX_COMMANDS]abi.Draw_Command
text: [abi.MAX_TEXT_BYTES]u8
assets: [abi.MAX_GRAPHICS_BYTES]u8
@(export) runtime_batch :: proc "c" () -> u32 { return u32(uintptr(&batch)) }
@(export) runtime_text :: proc "c" () -> u32 { return u32(uintptr(&text)) }
@(export) runtime_assets :: proc "c" () -> u32 { return u32(uintptr(&assets)) }
@(export) runtime_load_graphics :: proc "c" (size: u32) -> u32 {
    context = runtime.default_context()
    if size > abi.MAX_GRAPHICS_BYTES {return 0}
    return u32(core.load_graphics(assets[:size]))
}
@(export) runtime_render_batch :: proc "c" (count, size: u32) -> u32 {
    context = runtime.default_context()
    if count > abi.MAX_COMMANDS || size > abi.MAX_TEXT_BYTES {return 0}
    return u32(core.render_batch(batch[:count],text[:size]))
}
@(export) runtime_commands :: proc "c" () -> u32 { return u32(uintptr(&commands)) }
@(export) runtime_render_commands :: proc "c" (count: u32) -> u32 {
    context = runtime.default_context()
    if count > abi.MAX_COMMANDS { return 0 }
    return u32(core.render_commands(commands[:count]))
}
@(export) runtime_init :: proc "c" () {
    context = runtime.default_context()
    core.init()
}
@(export) runtime_frame :: proc "c" () -> u32 { return u32(uintptr(&frame)) }
@(export) runtime_pixels :: proc "c" () -> u32 { return u32(uintptr(&core.pixels)) }
@(export) runtime_sample :: proc "c" () -> u32 { return u32(uintptr(&core.sample)) }
@(export) runtime_render :: proc "c" () -> u32 {
    context = runtime.default_context()
    return u32(core.render(frame))
}
@(export) runtime_hash :: proc "c" () -> u32 {
    context = runtime.default_context()
    return core.hash()
}

@(export) runtime_display :: proc "c" (mode: u32) -> u32 { context = runtime.default_context(); return u32(core.set_display(mode)) }


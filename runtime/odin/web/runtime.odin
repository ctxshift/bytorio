package main

import "base:runtime"
import abi "../abi"
import core "../core"

frame: abi.Frame
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

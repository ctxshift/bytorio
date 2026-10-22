package main

import w "../resource_protocol"
import resources "../resources"
import "base:runtime"

ogg_request_buffer: [w.oggRequestWords]u32
ogg_pcm: [w.oggChunkFrames * 2]f32
@(export)
runtime_ogg_request :: proc "c" (index: u32) -> u32 {
    context = runtime.default_context()
    ogg_request_buffer = resources.ogg_request(&resource_registry, index)
    return u32(uintptr(&ogg_request_buffer))
}
@(export)
runtime_ogg_pcm :: proc "c" () -> u32 { return u32(uintptr(&ogg_pcm)) }
@(export)
runtime_ogg_feed :: proc "c" (index, id, low, high, frames: u32) -> u32 {
    context = runtime.default_context()
    if frames > w.oggChunkFrames { return 0 }
    return u32(
        resources.ogg_feed(
            &resource_registry,
            index,
            id,
            u64(low) | u64(high) << 32,
            ogg_pcm[:int(frames) * 2],
        ),
    )
}

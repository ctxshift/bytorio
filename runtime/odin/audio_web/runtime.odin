package main

import audio "../audio"
import w "../resource_protocol"
import "base:runtime"

engine: ^audio.Engine
packet: [w.maxAudioPacketBytes]u8
feedback: [w.maxAudioFeedbackBytes]u8
output: [w.maxAudioDeviceBlock * 2]f32
@(export)
audio_init :: proc "c" () -> u32 {
    context = runtime.default_context()
    context.allocator = runtime.default_wasm_allocator()
    audio.close(engine)
    engine = audio.create()
    return u32(engine != nil)
}
@(export)
audio_packet :: proc "c" () -> u32 { return u32(uintptr(&packet)) }
@(export)
audio_submit :: proc "c" (bytes: u32) -> u32 {
    context = runtime.default_context()
    if bytes > w.maxAudioPacketBytes { return 0 }
    return u32(audio.import_batch(engine, packet[:bytes]))
}
@(export)
audio_render :: proc "c" (frames, rate: u32) -> u32 {
    context = runtime.default_context()
    if frames == 0 ||
       frames > w.maxAudioDeviceBlock ||
       rate < w.minSampleRate ||
       rate > w.maxAudioDeviceRate { return 0 }
    audio.render(engine, output[:int(frames) * 2], rate)
    return u32(uintptr(&output))
}
@(export)
audio_pause :: proc "c" (paused: u32) {
    context = runtime.default_context()
    audio.pause(engine, paused != 0)
}
@(export)
audio_feedback :: proc "c" () -> u32 {
    context = runtime.default_context()
    return u32(audio.feedback(engine, feedback[:]))
}
@(export)
audio_feedback_pointer :: proc "c" () -> u32 { return u32(uintptr(&feedback)) }

@(export)
audio_output_pointer :: proc "c" () -> u32 { return u32(uintptr(&output)) }

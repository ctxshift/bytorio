package main

import audio "../audio"
import w "../resource_protocol"
import "base:runtime"

audio_packet: [w.maxAudioPacketBytes]u8
audio_output: [w.maxAudioDeviceBlock * 2]f32
audio_feedback_buffer: [w.maxAudioFeedbackBytes]u8
@(export)
runtime_audio_enabled :: proc "c" () -> u32 { return u32(resource_registry.audio != nil) }
@(export)
runtime_audio_batches_available :: proc "c" () -> u32 {
    context = runtime.default_context()
    if resource_registry.audio == nil { return w.maxAudioBatches }
    return audio.producer_batches_available(resource_registry.audio)
}
@(export)
runtime_audio_packet :: proc "c" () -> u32 { return u32(uintptr(&audio_packet)) }
@(export)
runtime_audio_export :: proc "c" () -> i32 {
    context = runtime.default_context()
    return i32(audio.export_batch(resource_registry.audio, audio_packet[:]))
}
@(export)
runtime_audio_feedback :: proc "c" (size: u32) -> u32 {
    context = runtime.default_context()
    if size > w.maxAudioFeedbackBytes { return 0 }
    return u32(audio.import_feedback(resource_registry.audio, audio_feedback_buffer[:size]))
}
@(export)
runtime_audio_feedback_pointer :: proc "c" () -> u32 {
    return u32(uintptr(&audio_feedback_buffer))
}
// Offline reference export used by conformance; the interactive browser renders
// this same module's mixer in the independent AudioWorklet instance.
@(export)
runtime_audio_render :: proc "c" (frames, rate: u32) -> u32 {
    context = runtime.default_context()
    if frames == 0 ||
       frames > w.maxAudioDeviceBlock ||
       rate < w.minSampleRate ||
       rate > w.maxAudioDeviceRate { return 0 }
    audio.render(resource_registry.audio, audio_output[:int(frames) * 2], rate)
    return u32(uintptr(&audio_output))
}
@(export)
runtime_audio_pause :: proc "c" (paused: u32) {
    context = runtime.default_context()
    audio.pause(resource_registry.audio, paused != 0)
}

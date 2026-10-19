package audio

import w "../../../runtime/odin/resource_protocol"
import data "../data"
import t "../resource"
Sample :: distinct t.Handle
Sample_Desc :: struct {
    frames, channels: u32,
    rate:             u32,
}
Frame_Range :: struct {
    first, frames: u32,
}
sample :: proc(desc: Sample_Desc, pcm: data.PCM_Buffer) -> Sample {
    if !t.valid(
        desc.frames > 0 &&
        (desc.channels == 1 || desc.channels == 2) &&
        desc.rate >= 8000 &&
        desc.rate <= 96000 &&
        u64(desc.frames) * u64(desc.channels) * 4 <= w.maxResourceBytes,
        "invalid sample descriptor",
    ) {

        return {}
    }
    handle := t.reserve(2, w.format_f32, desc.channels)
    args := [8]u32{w.format_f32, desc.frames, desc.channels, desc.rate, 0, 0, 0, 0}
    t.emit(w.op_create_sample, handle, args[:])
    result := Sample(handle)
    if len(pcm.samples) > 0 {

        write(result, {0, u32(pcm.frames)}, pcm)
    }
    return result
}
write :: proc(target: Sample, range: Frame_Range, pcm: data.PCM_Buffer) {
    handle := t.Handle(target)
    if !t.check(handle, 2) {

        return
    }
    if !t.valid(
        pcm.frames > 0 &&
        pcm.channels == int(t.slots[(handle.id & 65535) - 1].channels) &&
        range.frames == u32(pcm.frames) &&
        len(pcm.samples) == pcm.frames * pcm.channels,
        "PCM descriptor does not match buffer",
    ) {

        return
    }
    args := [8]u32{range.first, range.frames, 0, 0, 0, 0, 0, 0}
    bytes := (cast([^]u8)raw_data(pcm.samples))[:len(pcm.samples) * 4]
    t.emit(w.op_write_sample, handle, args[:], bytes)
}
destroy :: proc(target: Sample) {

    t.destroy(t.Handle(target), 2)
}

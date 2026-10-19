package resources

import audio "../audio"
import w "../resource_protocol"

audio_command :: proc(
    t: ^Transaction,
    op, id: u32,
    a: [8]u32,
    data: []u8,
    phase: u32,
    tick: u64,
) -> bool {
    r := t.registry
    if phase == 2 { return fail(r, "audio commands require init/update") }
    used := 0
    switch op {
    case w.op_audio_bus:
        used = 2
    case w.op_audio_stream, w.op_audio_destroy:
        used = 0
    case w.op_audio_play_sample:
        used = 8
    case w.op_audio_play_stream:
        used = 6
    case w.op_audio_stop:
        used = 2
    case w.op_audio_release, w.op_audio_stream_write:
        used = 3
    case w.op_audio_voice_control:
        used = 5
    case w.op_audio_bus_gain:
        used = 4
    case:
        return fail(r, "unknown audio command")
    }
    for i in used ..< len(a) {
        if a[i] != 0 { return fail(r, "nonzero reserved audio descriptor field") }
    }
    if r.audio == nil {
        r.audio = audio.create()
        if r.audio == nil { return fail(r, "cannot preallocate audio engine") }
        t.audio_created = true
        t.retained += audio.RESERVED_BYTES
        if t.retained > t.budget { return fail(r, "audio reservations exceed resource budget") }
    }
    if !t.audio.active {
        ok: bool
        t.audio, ok = audio.begin(r.audio)
        if !ok { return fail(r, "audio queue backpressure") }
    }
    at := u64(a[0]) | u64(a[1]) << 32
    now := tick * w.audioFramesPerTick
    c := audio.Command {
        op = op,
        id = id,
        at = at,
    }
    model := &t.audio.model
    if op == w.op_audio_bus || op == w.op_audio_stream || op == w.op_audio_destroy { c.at = now }
    if c.at < now || c.at > now + w.audioHorizonFrames || c.at > w.audioMaxExactFrame {
        return fail(r, "audio event outside logical scheduling horizon")
    }
    expects_data := op == w.op_audio_play_sample || op == w.op_audio_stream_write
    if !expects_data && len(data) != 0 { return fail(r, "unexpected audio payload") }
    switch op {
    case w.op_audio_bus, w.op_audio_stream:
        slot := unused(t, id)
        if slot == nil { return fail(r, "invalid audio resource slot") }
        if op == w.op_audio_bus {
            parent, ok := audio.bus_index(model, a[0])
            gain := transmute(f32)a[1]
            if !ok ||
               !audio.finite(gain, 0, 4) { return fail(r, "invalid audio bus parent or gain") }
            found := false
            for &bus, i in model.buses {
                if i == 0 || bus.live { continue }
                bus = {
                    id     = id,
                    parent = a[0],
                    live   = true,
                }
                c.id, c.resource, c.parent, c.gain = u32(i), id, parent, gain
                found = true; break
            }
            if !found { return fail(r, "audio bus capacity exceeded") }
            slot.kind, slot.link = .Bus, a[0]
        } else {
            found := false
            for &stream, i in model.streams {
                if stream.live { continue }
                stream = {
                    id   = id,
                    live = true,
                }
                c.id, c.resource = u32(i), id
                found = true; break
            }
            if !found { return fail(r, "PCM stream capacity exceeded") }
            slot.kind = .Stream
        }
        bytes, ok := allocate(t, 32 if slot.kind == .Bus else w.maxStreamFrames * 2 * 4)
        if !ok { return false }
        slot.data = bytes
        if slot.kind == .Bus { put32(bytes, 0, a[0]); put32(bytes, 4, a[1]) }
    case w.op_audio_destroy:
        slot := lookup(t, id)
        if id == 0 ||
           slot == nil ||
           (slot.kind != .Bus &&
                   slot.kind != .Stream) { return fail(r, "invalid audio destruction") }
        c.parameter, c.resource = u32(slot.kind), id
        if slot.kind == .Bus {
            if referenced(t, id) { return fail(r, "audio bus still has child buses") }
            i, ok := audio.bus_index(model, id)
            if !ok { return fail(r, "unknown audio bus") }
            c.id = i; model.buses[i] = {}
        } else {
            i, ok := audio.stream_index(model, id)
            if !ok { return fail(r, "unknown PCM stream") }
            c.id = i; model.streams[i] = {}
        }
        original := &r.slots[(id & w.handleIndexMask) - 1]
        if raw_data(slot.data) !=
           raw_data(original.data) { t.retained -= len(slot.data); delete(slot.data) }
        slot^ = Slot {
            generation = slot.generation + 1,
        }
    case w.op_audio_play_sample, w.op_audio_play_stream:
        if id >= w.maxVoices { return fail(r, "invalid voice slot") }
        bus, ok := audio.bus_index(model, a[3])
        if !ok { return fail(r, "invalid voice bus") }
        c.bus, c.parent, c.resource = bus, a[3], a[2]
        if op == w.op_audio_play_sample {
            slot := lookup(t, a[2], .Sample)
            c.rate, c.gain, c.pan = transmute(f32)a[4], transmute(f32)a[5], transmute(f32)a[6]
            if slot == nil ||
               !audio.finite(c.rate, 0.0625, 16) ||
               !audio.finite(c.gain, 0, 4) ||
               !audio.finite(c.pan, -1, 1) ||
               a[7] > 1 ||
               len(data) != 8 {
                return fail(r, "invalid sample playback descriptor")
            }
            c.frames, c.channels, c.source_rate = slot.width, slot.channels, slot.rate
            if a[7] != 0 {
                c.loop_start, c.loop_end = u32le(data, 0), u32le(data, 4)
                if c.loop_start >= c.loop_end ||
                   c.loop_end > slot.width { return fail(r, "invalid sample loop range") }
            } else if u32le(data, 0) != 0 ||
               u32le(data, 4) != 0 { return fail(r, "noncanonical disabled loop") }
            c.lease, c.page, ok = audio.snapshot(&t.audio, slot.data)
            if !ok { return fail(r, "audio snapshot budget exceeded") }
        } else {
            _, valid := audio.stream_index(model, a[2])
            c.rate, c.gain, c.pan = 1, transmute(f32)a[4], transmute(f32)a[5]
            if !valid ||
               !audio.finite(c.gain, 0, 4) ||
               !audio.finite(c.pan, -1, 1) { return fail(r, "invalid stream playback descriptor") }
        }
    case w.op_audio_stop, w.op_audio_release, w.op_audio_voice_control:
        if id >= w.maxVoices { return fail(r, "invalid voice slot") }
        if op == w.op_audio_release { c.ramp = a[2] }
        if op == w.op_audio_voice_control {
            c.parameter, c.ramp = a[2], a[4]
            c.gain, c.pan = transmute(f32)a[3], transmute(f32)a[3]
            if a[2] > 1 ||
               (a[2] == 0 && !audio.finite(c.gain, 0, 4)) ||
               (a[2] == 1 &&
                       !audio.finite(c.pan, -1, 1)) { return fail(r, "invalid voice control") }
        }
        if c.ramp > w.audioHorizonFrames { return fail(r, "audio ramp outside horizon") }
    case w.op_audio_bus_gain:
        bus, ok := audio.bus_index(model, id)
        c.id, c.resource, c.gain, c.ramp = bus, id, transmute(f32)a[2], a[3]
        if !ok ||
           !audio.finite(c.gain, 0, 4) ||
           c.ramp > w.audioHorizonFrames { return fail(r, "invalid bus gain control") }
    case w.op_audio_stream_write:
        index, ok := audio.stream_index(model, id)
        if !ok ||
           a[2] == 0 ||
           a[2] > w.maxStreamFrames ||
           u64(len(data)) != u64(a[2]) * 8 { return fail(r, "invalid PCM stream write") }
        if c.at <
           audio.load(&r.audio.published_frame) { return fail(r, "PCM stream write is late") }
        for i := 0; i < len(data); i += 4 {
            if !audio.finite(
                transmute(f32)u32le(data, i),
                -1,
                1,
            ) { return fail(r, "invalid PCM stream value") }
        }
        stream := &model.streams[index]
        count, frames := 0, u64(a[2])
        current := audio.load(&r.audio.published_frame)
        for interval in stream.intervals[:stream.count] {
            if interval.end <= current { continue }
            if c.at < interval.end &&
               c.at + u64(a[2]) >
                   interval.first { return fail(r, "overlapping PCM stream writes") }
            frames += interval.end - max(current, interval.first)
            stream.intervals[count] = interval; count += 1
        }
        if count == w.maxStreamChunks ||
           frames > w.maxStreamFrames { return fail(r, "PCM stream queue backpressure") }
        stream.intervals[count] = {c.at, c.at + u64(a[2])}; stream.count = count + 1
        c.id, c.resource, c.frames, c.channels = index, id, a[2], 2
        c.lease, c.page, ok = audio.snapshot(&t.audio, data)
        if !ok { return fail(r, "audio snapshot budget exceeded") }
    case:
        return fail(r, "unknown audio command")
    }
    // The fixed reservation includes both hosts' preallocated PCM and transfer pools.
    if t.retained > t.budget {
        audio.release_lease(r.audio, c.lease)
        return fail(r, "audio copies exceed resource budget")
    }
    if !audio.append(&t.audio, c) {
        audio.release_lease(r.audio, c.lease)
        return fail(r, "audio event queue backpressure")
    }
    if c.lease != 0 { t.copy_bytes += u64(c.frames) * u64(c.channels) * 4 }
    return true
}

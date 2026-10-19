package resources

import audio "../audio"
import w "../resource_protocol"

prepare_audio :: proc(t: ^Transaction) -> bool {
    r := t.registry
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
    return true
}
queue_audio :: proc(t: ^Transaction, c: audio.Command) -> bool {
    if !audio.append(&t.audio, c) {
        audio.release_lease(t.registry.audio, c.lease)
        return fail(t.registry, "audio queue backpressure")
    }
    if c.lease != 0 { t.copy_bytes += u64(c.frames) * u64(c.channels) * 4 }
    return true
}
ensure_source :: proc(t: ^Transaction, id: u32, now: u64) -> bool {
    slot := lookup(t, id)
    if slot == nil ||
       (slot.kind != .Sample &&
               slot.kind != .Wavetable) { return fail(t.registry, "invalid synthesis source") }
    _, exists := audio.source_info(&t.audio.model, id)
    if exists { return true }
    for at := 0; at < len(slot.data); at += 4 {
        if !audio.finite(
            transmute(f32)u32le(slot.data, at),
            -1,
            1,
        ) { return fail(t.registry, "synthesis PCM outside range") }
    }
    c := audio.Command {
        op          = w.op_audio_source,
        id          = id,
        at          = now,
        frames      = slot.width,
        channels    = slot.channels,
        source_rate = slot.rate,
    }
    info := audio.Source_Info {
        id       = id,
        frames   = slot.width,
        channels = slot.channels,
        rate     = slot.rate,
    }
    if slot.kind == .Wavetable {
        c.loop_start, c.loop_end = slot.width, slot.height
        c.frames = slot.width * slot.height
        info.waves = slot.height
    }
    ok: bool
    c.lease, c.page, ok = audio.snapshot(&t.audio, slot.data)
    if !ok { return fail(t.registry, "synthesis source snapshot exhausted") }
    if !queue_audio(t, c) { return false }
    t.audio.model.sources[audio.source_slot(id)] = info
    return true
}
register_graph_sources :: proc(t: ^Transaction, b: []u8, limit: u32, now: u64) -> bool {
    if len(b) < w.graphHeaderBytes { return false }
    count := u32le(b, 0)
    if count == 0 ||
       count > limit ||
       u64(len(b)) != w.graphHeaderBytes + u64(count) * w.graphNodeBytes { return false }
    for i in 0 ..< int(count) {
        node := audio.decode_node(b[w.graphHeaderBytes + i * w.graphNodeBytes:][:w.graphNodeBytes])
        if node.kind == w.node_sample || node.kind == w.node_wavetable {
            if !ensure_source(t, node.source, now) { return false }
        }
    }
    return true
}
source_registered :: proc(t: ^Transaction, id: u32) -> bool {
    if t.registry.audio == nil { return false }
    model := &t.audio.model if t.audio.active else &t.registry.audio.model
    _, ok := audio.source_info(model, id)
    return ok
}
destroy_source :: proc(t: ^Transaction, id: u32, tick: u64) -> bool {
    if !source_registered(t, id) { return true }
    if !prepare_audio(t) { return false }
    t.audio.model.sources[audio.source_slot(id)] = {}
    return queue_audio(
        t,
        {op = w.op_audio_source_destroy, id = id, at = tick * w.audioFramesPerTick},
    )
}
graph_references :: proc(b: []u8, id: u32) -> bool {
    if len(b) < w.graphHeaderBytes { return false }
    count := u32le(b, 0)
    for i in 0 ..< int(count) {
        if u32le(b, w.graphHeaderBytes + i * w.graphNodeBytes + 12) == id { return true }
    }
    return false
}
synthesis_command :: proc(t: ^Transaction, op, id: u32, a: [8]u32, data: []u8, tick: u64) -> bool {
    r := t.registry
    used := 0
    switch op {
    case w.op_audio_wavetable:
        used = 2
    case w.op_audio_instrument, w.op_audio_destroy_synth:
        used = 0
    case w.op_audio_edit:
        used = 4
    case w.op_audio_note_on:
        used = 7
    case w.op_audio_note_off, w.op_audio_effects:
        used = 2
    case w.op_audio_node_control:
        used = 8
    case:
        return fail(r, "unknown synthesis opcode")
    }
    for i in used ..< len(a) { if a[i] != 0 { return fail(r, "nonzero synthesis padding") } }
    if !prepare_audio(t) { return false }
    now := tick * w.audioFramesPerTick
    c := audio.Command {
        op = op,
        id = id,
        at = u64(a[0]) | u64(a[1]) << 32,
    }
    if op == w.op_audio_wavetable ||
       op == w.op_audio_instrument ||
       op == w.op_audio_destroy_synth { c.at = now }
    if c.at < now ||
       c.at > now + w.audioHorizonFrames ||
       c.at > w.audioMaxExactFrame { return fail(r, "synthesis schedule outside horizon") }
    if op != w.op_audio_wavetable &&
       op != w.op_audio_instrument &&
       op != w.op_audio_edit &&
       op != w.op_audio_effects &&
       len(data) != 0 {
        return fail(r, "unexpected synthesis payload")
    }
    switch op {
    case w.op_audio_wavetable:
        slot := unused(t, id)
        if slot == nil ||
           a[0] < w.minWaveFrames ||
           a[0] > w.maxWaveFrames ||
           a[0] & (a[0] - 1) != 0 ||
           a[1] == 0 ||
           a[1] > w.maxWaves ||
           u64(len(data)) !=
               u64(a[0]) * u64(a[1]) * 4 { return fail(r, "invalid wavetable descriptor") }
        bytes, ok := allocate(t, len(data))
        if !ok { return false }
        copy(bytes, data)
        slot.kind, slot.width, slot.height, slot.channels, slot.rate, slot.data =
            .Wavetable, a[0], a[1], 1, w.audioRate, bytes
        return ensure_source(t, id, now)
    case w.op_audio_instrument:
        slot := unused(t, id)
        if slot == nil ||
           !register_graph_sources(t, data, w.maxInstrumentNodes, now) ||
           !audio.validate_graph(
                   data,
                   &t.audio.model,
                   false,
                   false,
               ) { return fail(r, "invalid typed instrument graph") }
        found := false
        for &d in t.audio.model.definitions {
            if d.id == 0 {d = {
                    id      = id,
                    count   = u32le(data, 0),
                    history = u32le(data, 4),
                }; found = true; break}
        }
        if !found { return fail(r, "instrument capacity exceeded") }
        bytes, ok := allocate(t, len(data))
        if !ok { return false }
        copy(bytes, data)
        slot.kind, slot.data = .Instrument, bytes
        c.frames, c.channels = u32(len(data) / 4), 1
        c.lease, c.page, ok = audio.snapshot(&t.audio, data)
        if !ok { return fail(r, "instrument snapshot exhausted") }
    case w.op_audio_destroy_synth:
        slot := lookup(t, id)
        if slot == nil ||
           (slot.kind != .Instrument && slot.kind != .Wavetable) ||
           referenced(
               t,
               id,
           ) { return fail(r, "synthesis resource still referenced or wrong kind") }
        c.parameter = u32(slot.kind)
        if slot.kind == .Wavetable {
            if !destroy_source(t, id, tick) { return false }
        } else {
            for &d in t.audio.model.definitions { if d.id == id { d = {}; break } }
            if !queue_audio(t, c) { return false }
        }
        original := &r.slots[audio.source_slot(id)]
        if raw_data(slot.data) !=
           raw_data(original.data) { t.retained -= len(slot.data); delete(slot.data) }
        slot^ = {
            generation = slot.generation + 1,
        }
        return true
    case w.op_audio_edit:
        slot := lookup(t, id)
        if slot == nil ||
           !ensure_source(t, id, now) ||
           a[3] == 0 ||
           u64(a[2]) + u64(a[3]) > u64(slot.width) * u64(max(1, slot.height)) ||
           u64(len(data)) !=
               u64(a[3]) * u64(slot.channels) * 4 { return fail(r, "invalid source edit range") }
        for at := 0;
            at < len(data);
            at += 4 { if !audio.finite(transmute(f32)u32le(data, at), -1, 1) { return fail(r, "invalid source edit PCM") } }
        c.parameter, c.frames, c.channels = a[2], a[3], slot.channels
        ok: bool
        c.lease, c.page, ok = audio.snapshot(&t.audio, data)
        if !ok { return fail(r, "source edit snapshot exhausted") }
    case w.op_audio_note_on:
        instrument, ok := audio.definition(&t.audio.model, a[2])
        bus, bus_ok := audio.bus_index(&t.audio.model, a[3])
        c.rate, c.gain, c.pan = transmute(f32)a[4], transmute(f32)a[5], transmute(f32)a[6]
        if id >= w.maxVoices ||
           !ok ||
           !bus_ok ||
           !audio.finite(c.rate, 1, 20000) ||
           !audio.finite(c.gain, 0, 1) ||
           !audio.finite(c.pan, -1, 1) { return fail(r, "invalid note descriptor") }
        c.resource, c.bus, c.parent, c.frames, c.channels =
            a[2], bus, a[3], max(1, instrument.history), 1
        c.lease, c.page, ok = audio.reserve_snapshot(&t.audio, int(c.frames) * 4)
        if !ok { return fail(r, "note DSP history budget exhausted") }
    case w.op_audio_note_off:
        if id >= w.maxVoices { return fail(r, "invalid note voice") }
    case w.op_audio_effects:
        if c.at !=
           now { return fail(r, "effects topology changes require the current simulation frame") }
        bus, ok := audio.bus_index(&t.audio.model, id)
        if !ok { return fail(r, "invalid effects bus") }
        slot := lookup(t, id, .Bus) if id != 0 else &t.audio_master
        if slot == nil { return fail(r, "invalid bus resource") }
        c.id, c.resource = bus, id
        if len(data) != 0 {
            if !register_graph_sources(t, data, w.maxBusNodes, now) ||
               !audio.validate_graph(
                       data,
                       &t.audio.model,
                       true,
                       false,
                   ) { return fail(r, "invalid typed effects graph") }
            c.frames, c.channels = u32(len(data) / 4) + u32le(data, 4), 1
            c.lease, c.page, ok = audio.reserve_snapshot(&t.audio, int(c.frames) * 4)
            if !ok { return fail(r, "effects history budget exhausted") }
            target := audio.command_bytes(r.audio, c)
            copy(target, data)
        }
        bytes, allocated := allocate(t, 32 + len(data))
        if !allocated { audio.release_lease(r.audio, c.lease); return false }
        copy(bytes, slot.data[:min(32, len(slot.data))])
        copy(bytes[32:], data)
        original := &r.slots[audio.source_slot(id)] if id != 0 else &r.audio_master
        if raw_data(slot.data) !=
           raw_data(original.data) { t.retained -= len(slot.data); delete(slot.data) }
        slot.data = bytes
    case w.op_audio_node_control:
        if a[7] > 1 || a[6] > w.audioHorizonFrames { return fail(r, "invalid typed node control") }
        graph: []u8
        if a[7] == 0 {
            slot := lookup(t, a[2], .Instrument)
            if id >= w.maxVoices ||
               slot == nil { return fail(r, "invalid instrument control target") }
            graph = slot.data
            c.resource = a[2]
        } else {
            bus, ok := audio.bus_index(&t.audio.model, id)
            slot := lookup(t, id, .Bus) if id != 0 else &t.audio_master
            if !ok ||
               slot == nil ||
               len(slot.data) <= 32 ||
               a[2] != 0 { return fail(r, "invalid effects control target") }
            graph = slot.data[32:]
            c.id, c.resource, c.parent = bus, id, 1
        }
        if a[3] >= u32le(graph, 0) { return fail(r, "invalid node index") }
        node := audio.decode_node(
            graph[w.graphHeaderBytes + int(a[3]) * w.graphNodeBytes:][:w.graphNodeBytes],
        )
        parameter, lo, hi, ok := audio.parameter_slot(node, a[4])
        value := transmute(f32)a[5]
        if !ok ||
           !audio.finite(
                   value,
                   lo,
                   hi,
               ) { return fail(r, "parameter does not match node kind or bounds") }
        if a[4] == w.param_wave {
            info, _ := audio.source_info(&t.audio.model, node.source)
            if value > f32(info.waves - 1) { return fail(r, "wave selection outside source") }
        }
        c.loop_start, c.loop_end, c.parameter, c.gain, c.ramp =
            a[3], node.kind, u32(parameter), value, a[6]
    }
    return queue_audio(t, c)
}

package audio_mixer

import w "../resource_protocol"

command_data :: proc(e: ^Engine, c: Command) -> []f32 {
    if c.lease == 0 { return nil }
    return e.pool[int(c.page) * w.audioPageFrames:][:int(c.frames * c.channels)]
}
command_bytes :: proc(e: ^Engine, c: Command) -> []u8 {
    data := command_data(e, c)
    return (cast([^]u8)raw_data(data))[:len(data) * 4]
}
graph_by_id :: proc(e: ^Engine, id: u32) -> ^Graph {
    for &g in e.graphs { if g.id != 0 && g.id == id { return &g } }
    return nil
}
apply_synthesis :: proc(e: ^Engine, c: Command) {
    switch c.op {
    case w.op_audio_source:
        slot := source_slot(c.id)
        info := Source_Info {
            id       = c.id,
            frames   = c.frames,
            channels = c.channels,
            rate     = c.source_rate,
        }
        if c.loop_end != 0 { info.frames, info.waves = c.loop_start, c.loop_end }
        e.sources[slot] = {
            info  = info,
            lease = c.lease,
            data  = command_data(e, c),
        }
    case w.op_audio_source_destroy:
        slot := source_slot(c.id)
        source := &e.sources[slot]
        if source.info.id != c.id { break }
        for v, i in e.voices {
            if v.kind == 1 && v.resource == c.id { stop_voice(e, u32(i), w.audioReasonCancelled) }
        }
        finish(e, source.lease, NO_VOICE, 0)
        source^ = {}
    case w.op_audio_edit:
        source := &e.sources[source_slot(c.id)]
        if source.info.id == c.id {
            patch := command_data(e, c)
            copy(source.data[int(c.parameter * c.channels):][:len(patch)], patch)
            // A source becomes live when explicitly edited. Existing PCM voices
            // adopt its storage without resetting their playback position.
            for &v in e.voices {
                if v.kind == 1 && v.resource == c.id {
                    finish(e, v.lease, NO_VOICE, 0)
                    v.lease = 0
                    v.data = source.data
                }
            }
        }
        finish(e, c.lease, NO_VOICE, 0)
    case w.op_audio_instrument:
        for &g in e.graphs {
            if g.id != 0 { continue }
            g = decode_graph(command_bytes(e, c))
            g.id, g.lease = c.id, c.lease
            break
        }
    case w.op_audio_destroy_synth:
        if c.parameter == w.kindInstrument {
            for v, i in e.voices {
                if v.kind == 3 &&
                   v.resource == c.id { stop_voice(e, u32(i), w.audioReasonCancelled) }
            }
            g := graph_by_id(e, c.id)
            if g != nil { finish(e, g.lease, NO_VOICE, 0); g^ = {} }
        }
    case w.op_audio_note_on:
        g := graph_by_id(e, c.resource)
        if g == nil || !e.buses[c.bus].live || e.buses[c.bus].id != c.parent {
            finish(e, c.lease, c.id, w.audioReasonCancelled)
            break
        }
        stop_voice(e, c.id, w.audioReasonStopped)
        v := &e.voices[c.id]
        v^ = Voice {
            kind = 3,
            resource = c.resource,
            bus = c.bus,
            bus_id = c.parent,
            lease = c.lease,
            gain = {value = f64(c.gain), target = f64(c.gain)},
            pan = {value = f64(c.pan), target = f64(c.pan)},
        }
        start_synth(&v.synth, g^, command_data(e, c), c.rate)
    case w.op_audio_note_off:
        if e.voices[c.id].kind == 3 {
            s := &e.voices[c.id].synth
            release_synth(s)
            immediate := true
            for n, i in s.graph.nodes[:s.graph.count] {
                if n.kind == w.node_adsr &&
                   s.states[i].envelope.remaining != 0 { immediate = false }
            }
            if immediate { stop_voice(e, c.id, w.audioReasonStopped) }
        }
    case w.op_audio_effects:
        b := &e.buses[c.id]
        if !b.live || b.id != c.resource { finish(e, c.lease, NO_VOICE, 0); break }
        finish(e, b.effects.graph.lease, NO_VOICE, 0)
        if c.lease == 0 { b.effects = {}; break }
        bytes := command_bytes(e, c)
        g := decode_graph(bytes)
        g.id, g.lease = c.resource, c.lease
        data := command_data(e, c)
        start_synth(
            &b.effects,
            g,
            data[(w.graphHeaderBytes + int(g.count) * w.graphNodeBytes) / 4:],
        )
    case w.op_audio_node_control:
        target: ^Synth
        if c.parent == 0 {
            v := &e.voices[c.id]
            if v.kind == 3 && v.resource == c.resource { target = &v.synth }
        } else {
            b := &e.buses[c.id]
            if b.live && b.id == c.resource { target = &b.effects }
        }
        if target != nil &&
           c.loop_start < target.graph.count &&
           target.graph.nodes[c.loop_start].kind == c.loop_end &&
           valid_node_value(target.graph.nodes[c.loop_start], c.parameter, c.gain) {
            set_ramp(&target.states[c.loop_start].p[c.parameter], f64(c.gain), c.ramp)
        }
    }
}

valid_node_value :: proc(n: Node, slot: u32, value: f32) -> bool {
    for parameter in u32(w.param_frequency) ..= u32(w.param_release) {
        index, lo, hi, ok := parameter_slot(n, parameter)
        if ok && u32(index) == slot { return finite(value, lo, hi) }
    }
    return false
}
validate_prepared_synthesis :: proc(c: Command, bytes: []u8, model: ^Model) -> bool {
    switch c.op {
    case w.op_audio_source:
        i := source_slot(c.id)
        if model.sources[i].id != 0 { return false }
        model.sources[i] = {
            id       = c.id,
            frames   = c.frames,
            channels = c.channels,
            rate     = c.source_rate,
        }
        if c.loop_end !=
           0 { model.sources[i].frames, model.sources[i].waves = c.loop_start, c.loop_end }
    case w.op_audio_source_destroy:
        i := source_slot(c.id)
        if model.sources[i].id != c.id { return false }
        model.sources[i] = {}
    case w.op_audio_instrument:
        if !validate_graph(bytes, model, false, false) { return false }
        for &d in model.definitions {
            if d.id == c.id { return false }
        }
        found := false
        for &d in model.definitions {
            if d.id == 0 {
                d = {
                    id      = c.id,
                    count   = word(bytes, 0),
                    history = word(bytes, 4),
                }
                found = true
                break
            }
        }
        if !found { return false }
    case w.op_audio_destroy_synth:
        found := false
        for &d in model.definitions {
            if d.id == c.id { d = {}; found = true; break }
        }
        if !found { return false }
    case w.op_audio_note_on:
        d, ok := definition(model, c.resource)
        if !ok || c.frames != max(1, d.history) { return false }
        for at := 0; at < len(bytes); at += 4 { if word(bytes, at) != 0 { return false } }
    case w.op_audio_edit:
        info, ok := source_info(model, c.id)
        if !ok ||
           info.channels != c.channels ||
           u64(c.parameter) + u64(c.frames) >
               u64(info.frames) * u64(max(1, info.waves)) { return false }
    case w.op_audio_effects:
        if c.lease != 0 && !validate_graph(bytes, model, true, true) { return false }
    case w.op_audio_node_control:
        if !valid_node_value(
            Node{kind = c.loop_end, flags = w.maxDelayFrames},
            c.parameter,
            c.gain,
        ) { return false }
    }
    return true
}

// Validate prepared host commands independently before the worklet imports them.
valid_synthesis_command :: proc(c: Command) -> bool {
    slot := source_slot(c.id)
    valid_id := slot >= 0 && slot < w.maxSlots
    switch c.op {
    case w.op_audio_source:
        return(
            valid_id &&
            c.lease != 0 &&
            c.frames > 0 &&
            (c.channels == 1 || c.channels == 2) &&
            c.source_rate >= w.minSampleRate &&
            c.source_rate <= w.maxSampleRate &&
            (c.loop_end == 0 ||
                    (c.channels == 1 &&
                            c.loop_start >= w.minWaveFrames &&
                            c.loop_start <= w.maxWaveFrames &&
                            c.loop_start & (c.loop_start - 1) == 0 &&
                            c.loop_end <= w.maxWaves &&
                            u64(c.loop_start) * u64(c.loop_end) == u64(c.frames))) \
        )
    case w.op_audio_source_destroy:
        return valid_id && c.lease == 0
    case w.op_audio_instrument:
        return valid_id && c.lease != 0 && c.channels == 1 && c.frames >= w.graphHeaderBytes / 4
    case w.op_audio_edit:
        return valid_id && c.lease != 0 && c.frames > 0 && (c.channels == 1 || c.channels == 2)
    case w.op_audio_destroy_synth:
        return valid_id && c.parameter == w.kindInstrument && c.lease == 0
    case w.op_audio_note_on:
        return(
            c.id < w.maxVoices &&
            c.bus < w.maxBuses &&
            c.lease != 0 &&
            c.frames > 0 &&
            c.channels == 1 &&
            finite(c.rate, 1, 20000) &&
            finite(c.gain, 0, 1) &&
            finite(c.pan, -1, 1) \
        )
    case w.op_audio_note_off:
        return c.id < w.maxVoices && c.lease == 0
    case w.op_audio_effects:
        return(
            c.id < w.maxBuses &&
            (c.lease == 0 || (c.channels == 1 && c.frames >= w.graphHeaderBytes / 4)) \
        )
    case w.op_audio_node_control:
        return(
            c.parent <= 1 &&
            c.id < u32(w.maxBuses if c.parent == 1 else w.maxVoices) &&
            c.loop_start < u32(w.maxBusNodes if c.parent == 1 else w.maxInstrumentNodes) &&
            c.parameter < 8 &&
            c.lease == 0 &&
            finite(c.gain, -96000, 96000) \
        )
    }
    return false
}

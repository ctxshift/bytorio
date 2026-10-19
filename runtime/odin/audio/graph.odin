package audio_mixer

import w "../resource_protocol"
import "core:math"

Source_Info :: struct {
    id, frames, channels, rate, waves: u32,
}
Definition_Info :: struct {
    id, count, history: u32,
}
Node :: struct {
    kind, a, b, source, frequency_input, phase_input, gain_input, flags: u32,
    p:                                                                   [8]f32,
}
Graph :: struct {
    id, lease, count, history: u32,
    nodes:                     [w.maxInstrumentNodes]Node,
}
Source :: struct {
    info:  Source_Info,
    lease: u32,
    data:  []f32,
}
Node_State :: struct {
    p:                    [8]Ramp,
    phase, position:      f64,
    noise, stage, cursor: u32,
    envelope:             Ramp,
    integrator:           [2][2]f64,
}
Synth :: struct {
    graph:    Graph,
    states:   [w.maxInstrumentNodes]Node_State,
    history:  []f32,
    released: bool,
    pitch:    f64,
}

source_slot :: proc(id: u32) -> int { return int(id & w.handleIndexMask) - 1 }
source_info :: proc(model: ^Model, id: u32) -> (Source_Info, bool) {
    i := source_slot(id)
    if i < 0 || i >= w.maxSlots { return {}, false }
    info := model.sources[i]
    return info, info.id == id
}
definition :: proc(model: ^Model, id: u32) -> (Definition_Info, bool) {
    for d in model.definitions { if d.id != 0 && d.id == id { return d, true } }
    return {}, false
}
decode_node :: proc(b: []u8) -> Node {
    n := Node {
        kind            = word(b, 0),
        a               = word(b, 4),
        b               = word(b, 8),
        source          = word(b, 12),
        frequency_input = word(b, 16),
        phase_input     = word(b, 20),
        gain_input      = word(b, 24),
        flags           = word(b, 28),
    }
    for &p, i in n.p { p = transmute(f32)word(b, 32 + i * 4) }
    return n
}
decode_graph :: proc(b: []u8) -> Graph {
    g := Graph {
        count   = word(b, 0),
        history = word(b, 4),
    }
    for &n, i in g.nodes[:g.count] {
        n = decode_node(b[w.graphHeaderBytes + i * w.graphNodeBytes:][:w.graphNodeBytes])
    }
    return g
}
// Port types: 0 absent, 1 mono audio, 2 stereo audio, 3 scalar control.
validate_graph :: proc(b: []u8, model: ^Model, bus, with_history: bool) -> bool {
    if len(b) < w.graphHeaderBytes { return false }
    count, history := word(b, 0), word(b, 4)
    limit := u32(w.maxBusNodes if bus else w.maxInstrumentNodes)
    if count == 0 || count > limit || word(b, 8) != 0 || word(b, 12) != 0 { return false }
    header := w.graphHeaderBytes + int(count) * w.graphNodeBytes
    expected := u64(header) + (u64(history) * 4 if with_history else 0)
    if expected != u64(len(b)) || expected > w.maxAudioSnapshotBytes { return false }
    ports: [w.maxInstrumentNodes]u32
    needed := u64(0)
    for i in 0 ..< int(count) {
        n := decode_node(b[w.graphHeaderBytes + i * w.graphNodeBytes:][:w.graphNodeBytes])
        for value in n.p { if !finite(value, -1000000, 1000000) { return false } }
        used := node_parameter_count(n.kind)
        for j in used ..< len(n.p) { if n.p[j] != 0 { return false } }
        inputs := [5]u32{n.a, n.b, n.frequency_input, n.phase_input, n.gain_input}
        for input in inputs { if input != w.noNode && input >= u32(i) { return false } }
        a := u32(0) if n.a == w.noNode else ports[n.a]
        b_port := u32(0) if n.b == w.noNode else ports[n.b]
        for input in inputs[2:] { if input != w.noNode && ports[input] != 1 && ports[input] != 3 { return false } }
        if n.kind != w.node_wavetable &&
           (n.frequency_input != w.noNode || n.phase_input != w.noNode) { return false }
        if n.kind != w.node_gain && n.gain_input != w.noNode { return false }
        if n.kind != w.node_sample && n.kind != w.node_wavetable && n.source != 0 { return false }
        output := u32(0)
        switch n.kind {
        case w.node_input:
            if !bus || a != 0 || b_port != 0 { return false }; output = 2
        case w.node_sample, w.node_wavetable:
            info, ok := source_info(model, n.source)
            if !ok || a != 0 || b_port != 0 { return false }
            if n.kind == w.node_wavetable {
                if info.waves == 0 ||
                   !finite(n.p[0], 0, 20000) ||
                   !finite(n.p[1], 0, f32(info.waves - 1)) ||
                   !finite(n.p[2], -24000, 24000) ||
                   !finite(n.p[3], -16, 16) ||
                   !finite(n.p[4], -16, 16) { return false }
            } else {
                if info.waves != 0 || !finite(n.p[0], 0.0625, 16) || n.flags > 1 { return false }
                if n.flags != 0 &&
                   (n.p[1] < 0 ||
                           n.p[1] >= n.p[2] ||
                           n.p[2] > f32(info.frames) ||
                           math.floor(n.p[1]) != n.p[1] ||
                           math.floor(n.p[2]) != n.p[2]) { return false }
            }
            output = info.channels
        case w.node_noise:
            if a != 0 || b_port != 0 || n.flags == 0 { return false }; output = 1
        case w.node_constant:
            if a != 0 || b_port != 0 || !finite(n.p[0], -16, 16) { return false }; output = 3
        case w.node_mix:
            if a == 0 ||
               a == 3 ||
               b_port == 0 ||
               b_port == 3 ||
               !finite(n.p[0], -4, 4) ||
               !finite(n.p[1], -4, 4) { return false }
            output = max(a, b_port)
        case w.node_gain:
            if a == 0 ||
               a == 3 ||
               b_port != 0 ||
               !finite(n.p[0], -4, 4) ||
               !finite(n.p[1], -4, 4) { return false }
            output = a
        case w.node_adsr:
            if bus ||
               a != 0 ||
               b_port != 0 ||
               !finite(n.p[0], 0, w.maxDelayFrames) ||
               !finite(n.p[1], 0, w.maxDelayFrames) ||
               !finite(n.p[2], 0, 1) ||
               !finite(n.p[3], 0, w.maxDelayFrames) { return false }
            output = 3
        case w.node_lfo:
            if a != 0 ||
               b_port != 0 ||
               !finite(n.p[0], 0, 200) ||
               !finite(n.p[1], -16, 16) { return false }
            output = 3
        case w.node_filter:
            if a == 0 ||
               a == 3 ||
               b_port != 0 ||
               n.flags > 2 ||
               !finite(n.p[0], 20, 20000) ||
               !finite(n.p[1], 0, 0.95) { return false }
            output = a
        case w.node_delay:
            if a == 0 ||
               a == 3 ||
               b_port != 0 ||
               n.flags == 0 ||
               n.flags > w.maxDelayFrames ||
               !finite(n.p[0], 1, f32(n.flags)) ||
               !finite(n.p[1], -0.95, 0.95) ||
               !finite(n.p[2], 0, 1) { return false }
            needed += u64(n.flags) * 2
            output = a
        case w.node_pan:
            if a == 0 || a == 3 || b_port != 0 || !finite(n.p[0], -1, 1) { return false }
            output = 2
        case w.node_output:
            if a == 0 || a == 3 || b_port != 0 || i != int(count) - 1 { return false }; output = 2
        case:
            return false
        }
        if n.kind != w.node_sample &&
           n.kind != w.node_noise &&
           n.kind != w.node_filter &&
           n.kind != w.node_delay &&
           n.flags != 0 { return false }
        ports[i] = output
    }
    last := decode_node(
        b[w.graphHeaderBytes + (int(count) - 1) * w.graphNodeBytes:][:w.graphNodeBytes],
    )
    if last.kind != w.node_output ||
       needed != u64(history) ||
       needed * 4 > w.maxAudioSnapshotBytes { return false }
    if with_history {
        for at := header; at < len(b); at += 4 { if word(b, at) != 0 { return false } }
    }
    return true
}

node_parameter_count :: proc(kind: u32) -> int {
    switch kind {
    case w.node_wavetable:
        return 5
    case w.node_sample, w.node_delay:
        return 3
    case w.node_mix, w.node_gain, w.node_lfo, w.node_filter:
        return 2
    case w.node_adsr:
        return 4
    case w.node_constant, w.node_pan:
        return 1
    }
    return 0
}

parameter_slot :: proc(n: Node, parameter: u32) -> (slot: int, lo, hi: f32, ok: bool) {
    switch parameter {
    case w.param_frequency:
        if n.kind == w.node_wavetable { return 0, 0, 20000, true }
        if n.kind == w.node_lfo { return 0, 0, 200, true }
    case w.param_phase:
        if n.kind == w.node_wavetable { return 4, -16, 16, true }
        if n.kind == w.node_lfo { return 1, -16, 16, true }
    case w.param_wave:
        if n.kind == w.node_wavetable { return 1, 0, w.maxWaves - 1, true }
    case w.param_rate:
        if n.kind == w.node_sample { return 0, 0.0625, 16, true }
    case w.param_gain:
        if n.kind == w.node_gain || n.kind == w.node_mix { return 0, -4, 4, true }
        if n.kind == w.node_constant { return 0, -16, 16, true }
    case w.param_secondary_gain:
        if n.kind == w.node_mix { return 1, -4, 4, true }
    case w.param_depth:
        if n.kind == w.node_gain { return 1, -4, 4, true }
        if n.kind == w.node_wavetable { return 2, -24000, 24000, true }
    case w.param_pan:
        if n.kind == w.node_pan { return 0, -1, 1, true }
    case w.param_cutoff:
        if n.kind == w.node_filter { return 0, 20, 20000, true }
    case w.param_resonance:
        if n.kind == w.node_filter { return 1, 0, 0.95, true }
    case w.param_delay_frames:
        if n.kind == w.node_delay { return 0, 1, f32(n.flags), true }
    case w.param_feedback:
        if n.kind == w.node_delay { return 1, -0.95, 0.95, true }
    case w.param_wet:
        if n.kind == w.node_delay { return 2, 0, 1, true }
    case w.param_attack, w.param_decay, w.param_sustain, w.param_release:
        if n.kind == w.node_adsr {
            index := int(parameter - w.param_attack)
            return index, 0, 1 if index == 2 else w.maxDelayFrames, true
        }
    }
    return 0, 0, 0, false
}

start_synth :: proc(s: ^Synth, graph: Graph, history: []f32, frequency: f32 = 440) {
    s^ = Synth {
        graph   = graph,
        history = history,
        pitch   = f64(frequency) / 440,
    }
    for n, i in s.graph.nodes[:s.graph.count] {
        state := &s.states[i]
        for value, j in n.p {state.p[j] = {
                value  = f64(value),
                target = f64(value),
            }}
        state.noise = n.flags
        if n.kind == w.node_adsr { set_ramp(&state.envelope, 1, u32(n.p[0])) }
    }
}
release_synth :: proc(s: ^Synth) {
    if s.released { return }
    s.released = true
    for n, i in s.graph.nodes[:s.graph.count] {
        if n.kind == w.node_adsr {
            state := &s.states[i]
            state.stage = 3
            set_ramp(&state.envelope, 0, u32(state.p[3].value))
        }
    }
}
wave_value :: proc(data: []f32, size: u32, phase: f64, wave: u32) -> f64 {
    position := (phase - math.floor(phase)) * f64(size)
    first := u32(math.floor(position))
    second := (first + 1) % size
    a, b := f64(data[wave * size + first]), f64(data[wave * size + second])
    return a + (b - a) * (position - f64(first))
}
// Fixed polynomial coefficient definition avoids platform libm differences.
filter_g :: proc(cutoff: f64) -> f64 {
    x := math.PI * cutoff / w.audioRate
    x2 := x * x
    return x * (105 - 10 * x2) / (105 - 45 * x2 + x2 * x2)
}
synth_frame :: proc(
    e: ^Engine,
    s: ^Synth,
    input: [2]f64 = {},
) -> (
    result: [2]f64,
    finished: bool,
) {
    values: [w.maxInstrumentNodes][2]f64
    history_offset := 0
    has_envelope, envelopes_done := false, true
    for n, i in s.graph.nodes[:s.graph.count] {
        state := &s.states[i]
        p: [8]f64
        for r, j in state.p { p[j] = r.value }
        a, b: [2]f64
        if n.a != w.noNode { a = values[n.a] }
        if n.b != w.noNode { b = values[n.b] }
        value: [2]f64
        switch n.kind {
        case w.node_input:
            value = input
        case w.node_constant:
            value = {p[0], p[0]}
        case w.node_noise:
            x := state.noise
            x ~= x << 13; x ~= x >> 17; x ~= x << 5
            state.noise = x
            v := f64(x) / 2147483648.0 - 1
            value = {v, v}
        case w.node_lfo:
            phase := state.phase + p[1]
            phase -= math.floor(phase)
            v := 1 - 4 * math.abs(phase - 0.5)
            value = {v, v}
            state.phase += p[0] / w.audioRate
            state.phase -= math.floor(state.phase)
        case w.node_wavetable, w.node_sample:
            source := &e.sources[source_slot(n.source)]
            if source.info.id != n.source { break }
            if n.kind == w.node_wavetable {
                frequency := p[0] * s.pitch
                phase := state.phase + p[4]
                if n.frequency_input !=
                   w.noNode { frequency += values[n.frequency_input][0] * p[2] }
                if n.phase_input != w.noNode { phase += values[n.phase_input][0] * p[3] }
                wave := clamp(p[1], 0, f64(source.info.waves - 1))
                first := u32(math.floor(wave))
                second := min(first + 1, source.info.waves - 1)
                x := wave_value(source.data, source.info.frames, phase, first)
                y := wave_value(source.data, source.info.frames, phase, second)
                v := x + (y - x) * (wave - f64(first))
                value = {v, v}
                state.phase += clamp(frequency, -24000, 24000) / w.audioRate
                state.phase -= math.floor(state.phase)
            } else if state.position < f64(source.info.frames) {
                first := u32(math.floor(state.position))
                second := first + 1
                if n.flags != 0 && second >= u32(p[2]) {
                    second = u32(p[1])
                } else {
                    second = min(second, source.info.frames - 1)
                }
                for c in 0 ..< 2 {
                    channel := u32(c) if source.info.channels == 2 else 0
                    x := f64(source.data[first * source.info.channels + channel])
                    y := f64(source.data[second * source.info.channels + channel])
                    value[c] = x + (y - x) * (state.position - f64(first))
                }
                state.position += p[0] * s.pitch * f64(source.info.rate) / w.audioRate
                if n.flags != 0 &&
                   state.position >=
                       p[2] { state.position = p[1] + math.mod(state.position - p[1], p[2] - p[1]) }
            }
        case w.node_mix:
            for c in 0 ..< 2 { value[c] = a[c] * p[0] + b[c] * p[1] }
        case w.node_gain:
            gain := p[0]
            if n.gain_input != w.noNode { gain += values[n.gain_input][0] * p[1] }
            for c in 0 ..< 2 { value[c] = a[c] * clamp(gain, -16, 16) }
        case w.node_adsr:
            has_envelope = true
            for _ in 0 ..< 3 {
                if state.envelope.remaining != 0 { break }
                if state.stage == 0 {
                    state.stage = 1
                    set_ramp(&state.envelope, p[2], u32(p[1]))
                } else if state.stage == 1 {
                    state.stage = 2
                    state.envelope.value = p[2]
                } else { break }
            }
            if state.stage == 2 { state.envelope.value = p[2] }
            value = {state.envelope.value, state.envelope.value}
            advance(&state.envelope)
            envelopes_done = envelopes_done && state.stage == 3 && state.envelope.remaining == 0
        case w.node_filter:
            g := filter_g(p[0])
            k := 2 - 1.9 * p[1]
            coefficient := 1 / (1 + g * (g + k))
            for c in 0 ..< 2 {
                v3 := a[c] - state.integrator[c][1]
                v1 := coefficient * state.integrator[c][0] + g * coefficient * v3
                v2 := state.integrator[c][1] + g * v1
                state.integrator[c] = {
                    2 * v1 - state.integrator[c][0],
                    2 * v2 - state.integrator[c][1],
                }
                value[c] = v2 if n.flags == 0 else v1 if n.flags == 1 else a[c] - k * v1 - v2
                for &v in state.integrator[c] { if math.abs(v) < 1e-20 { v = 0 } }
            }
        case w.node_delay:
            frames := u32(p[0])
            read := (state.cursor + n.flags - frames) % n.flags
            for c in 0 ..< 2 {
                delayed := f64(s.history[history_offset + int(read) * 2 + c])
                s.history[history_offset + int(state.cursor) * 2 + c] = f32(
                    clamp(a[c] + delayed * p[1], -16, 16),
                )
                value[c] = a[c] * (1 - p[2]) + delayed * p[2]
            }
            state.cursor = (state.cursor + 1) % n.flags
            history_offset += int(n.flags) * 2
        case w.node_pan:
            value = {a[0] * min(1.0, 1 - p[0]), a[1] * min(1.0, 1 + p[0])}
        case w.node_output:
            value = a
        }
        for &v in value { v = clamp(v, -16, 16) }
        values[i] = value
        for &r in state.p { advance(&r) }
    }
    result = values[s.graph.count - 1]
    finished = s.released && (!has_envelope || envelopes_done)
    return
}

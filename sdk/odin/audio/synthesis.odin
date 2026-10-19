package audio

import mixer "../../../runtime/odin/audio"
import w "../../../runtime/odin/resource_protocol"
import data "../data"
import t "../resource"

Wavetable :: distinct t.Handle
Instrument :: distinct t.Handle
Node_Kind :: enum u32 {
    Input     = w.node_input,
    Sample    = w.node_sample,
    Wavetable = w.node_wavetable,
    Noise     = w.node_noise,
    Constant  = w.node_constant,
    Mix       = w.node_mix,
    Gain      = w.node_gain,
    ADSR      = w.node_adsr,
    LFO       = w.node_lfo,
    Filter    = w.node_filter,
    Delay     = w.node_delay,
    Pan       = w.node_pan,
    Output    = w.node_output,
}
Parameter :: enum u32 {
    Frequency      = w.param_frequency,
    Phase          = w.param_phase,
    Wave           = w.param_wave,
    Rate           = w.param_rate,
    Gain           = w.param_gain,
    Secondary_Gain = w.param_secondary_gain,
    Depth          = w.param_depth,
    Pan            = w.param_pan,
    Cutoff         = w.param_cutoff,
    Resonance      = w.param_resonance,
    Delay_Frames   = w.param_delay_frames,
    Feedback       = w.param_feedback,
    Wet            = w.param_wet,
    Attack         = w.param_attack,
    Decay          = w.param_decay,
    Sustain        = w.param_sustain,
    Release        = w.param_release,
}
Filter_Mode :: enum u32 {
    Lowpass,
    Bandpass,
    Highpass,
}
Optional_U32 :: union {
    u32,
}
Node_Input :: Optional_U32
Node_Source :: union {
    Sample,
    Wavetable,
}
Node :: struct {
    kind:                                                                              Node_Kind,
    input, other, frequency_input, phase_input, gain_input:                            Node_Input,
    source:                                                                            Node_Source,
    frequency_hz, gain, secondary_gain, rate, depth, sustain, cutoff_hz, wet:          Optional_F32,
    value, pan, resonance, feedback, wave, phase_cycles, fm_depth_hz, pm_depth_cycles: f32,
    attack_frames, decay_frames, release_frames, max_delay_frames:                     u32,
    loop_start, loop_end:                                                              u32,
    seed, delay_frames:                                                                Optional_U32,
    loop:                                                                              bool,
    filter_mode:                                                                       Filter_Mode,
}
Wavetable_Desc :: struct {
    frames, waves: u32,
}
Note_Options :: struct {
    at:       Optional_Frame,
    velocity: Optional_F32,
    pan:      f32,
    bus:      Bus,
}
node_input :: proc(value: Node_Input) -> u32 {
    n, ok := value.(u32)
    return n if ok else w.noNode
}
u32_value :: proc(value: Optional_U32, fallback: u32) -> u32 {
    n, ok := value.(u32)
    return n if ok else fallback
}
wire_node :: proc(n: Node) -> mixer.Node {
    source := u32(0)
    switch value in n.source {
    case Sample:
        h := t.Handle(value)
        _ = t.check(h, 2)
        source = h.id
    case Wavetable:
        h := t.Handle(value)
        _ = t.check(h, w.kindWavetable)
        source = h.id
    }
    result := mixer.Node {
        kind            = u32(n.kind),
        a               = node_input(n.input),
        b               = node_input(n.other),
        source          = source,
        frequency_input = node_input(n.frequency_input),
        phase_input     = node_input(n.phase_input),
        gain_input      = node_input(n.gain_input),
    }
    switch n.kind {
    case .Wavetable:
        result.p = {
            float_value(n.frequency_hz, 440),
            n.wave,
            n.fm_depth_hz,
            n.pm_depth_cycles,
            n.phase_cycles,
            0,
            0,
            0,
        }
    case .Sample:
        result.p = {float_value(n.rate, 1), f32(n.loop_start), f32(n.loop_end), 0, 0, 0, 0, 0}
        result.flags = u32(n.loop)
    case .Noise:
        result.flags = u32_value(n.seed, 1)
    case .Constant:
        result.p[0] = n.value
    case .Mix:
        result.p[0], result.p[1] = float_value(n.gain, 1), float_value(n.secondary_gain, 1)
    case .Gain:
        result.p[0], result.p[1] = float_value(n.gain, 1), float_value(n.depth, 1)
    case .ADSR:
        result.p = {
            f32(n.attack_frames),
            f32(n.decay_frames),
            float_value(n.sustain, 1),
            f32(n.release_frames),
            0,
            0,
            0,
            0,
        }
    case .LFO:
        result.p[0], result.p[1] = float_value(n.frequency_hz, 5), n.phase_cycles
    case .Filter:
        result.p[0], result.p[1], result.flags =
            float_value(n.cutoff_hz, 1000), n.resonance, u32(n.filter_mode)
    case .Delay:
        result.flags = n.max_delay_frames
        result.p[0], result.p[1], result.p[2] =
            f32(u32_value(n.delay_frames, n.max_delay_frames)), n.feedback, float_value(n.wet, 0.5)
    case .Pan:
        result.p[0] = n.pan
    case .Input, .Output:
    }
    return result
}
encode_graph :: proc(nodes: []Node, bytes: []u8, bus: bool) -> []u8 {
    limit := w.maxBusNodes if bus else w.maxInstrumentNodes
    if !t.valid(len(nodes) > 0 && len(nodes) <= limit, "invalid graph node count") { return nil }
    size := w.graphHeaderBytes + len(nodes) * w.graphNodeBytes
    output := bytes[:size]
    for &b in output { b = 0 }
    mixer.put(output, 0, u32(len(nodes)))
    history := u64(0)
    for n, i in nodes {
        encoded := wire_node(n)
        if n.kind == .Delay { history += u64(n.max_delay_frames) * 2 }
        target := output[w.graphHeaderBytes + i * w.graphNodeBytes:][:w.graphNodeBytes]
        words := [8]u32 {
            encoded.kind,
            encoded.a,
            encoded.b,
            encoded.source,
            encoded.frequency_input,
            encoded.phase_input,
            encoded.gain_input,
            encoded.flags,
        }
        for value, j in words { mixer.put(target, j * 4, value) }
        for value, j in encoded.p { mixer.put(target, 32 + j * 4, transmute(u32)value) }
    }
    if !t.valid(
        history <= w.maxAudioSnapshotBytes / 4,
        "graph history exceeds arena",
    ) { return nil }
    mixer.put(output, 4, u32(history))
    return output
}
wavetable :: proc(desc: Wavetable_Desc, pcm: data.PCM_Buffer) -> Wavetable {
    if !ready() ||
       !t.valid(
               pcm.channels == 1 &&
               pcm.frames == int(desc.frames * desc.waves) &&
               len(pcm.samples) == pcm.frames,
               "invalid wavetable buffer",
           ) { return {} }
    h := t.reserve(w.kindWavetable, w.format_f32, 1)
    args := [8]u32{desc.frames, desc.waves, 0, 0, 0, 0, 0, 0}
    t.emit(
        w.op_audio_wavetable,
        h,
        args[:],
        (cast([^]u8)raw_data(pcm.samples))[:len(pcm.samples) * 4],
    )
    return Wavetable(h)
}
instrument :: proc(nodes: []Node) -> Instrument {
    if !ready() { return {} }
    bytes: [w.graphHeaderBytes + w.maxInstrumentNodes * w.graphNodeBytes]u8
    graph := encode_graph(nodes, bytes[:], false)
    h := t.reserve(w.kindInstrument, 0)
    args: [8]u32
    t.emit(w.op_audio_instrument, h, args[:], graph)
    return Instrument(h)
}
edit_source :: proc(h: t.Handle, kind: u32, first: u32, pcm: data.PCM_Buffer, at: u64) {
    if !ready() ||
       !t.check(h, kind) ||
       !t.valid(
               pcm.frames > 0 && len(pcm.samples) == pcm.frames * pcm.channels,
               "invalid edit buffer",
           ) { return }
    lo, hi := schedule(at)
    args := [8]u32{lo, hi, first, u32(pcm.frames), 0, 0, 0, 0}
    t.emit(w.op_audio_edit, h, args[:], (cast([^]u8)raw_data(pcm.samples))[:len(pcm.samples) * 4])
}
edit_sample :: proc(target: Sample, first: u32, pcm: data.PCM_Buffer, at: u64 = ASAP) {
    edit_source(t.Handle(target), 2, first, pcm, at)
}
edit_wavetable :: proc(target: Wavetable, first: u32, pcm: data.PCM_Buffer, at: u64 = ASAP) {
    edit_source(t.Handle(target), w.kindWavetable, first, pcm, at)
}
note_on :: proc(v: Voice, inst: Instrument, frequency_hz: f32, opts: Note_Options = {}) {
    if !valid_voice(v) || !t.check(t.Handle(inst), w.kindInstrument) { return }
    lo, hi := schedule(frame_value(opts.at))
    args := [8]u32 {
        lo,
        hi,
        t.Handle(inst).id,
        bus_id(opts.bus),
        transmute(u32)frequency_hz,
        transmute(u32)float_value(opts.velocity, 1),
        transmute(u32)opts.pan,
        0,
    }
    t.emit(w.op_audio_note_on, {t.session, v.index}, args[:])
}
note_off :: proc(v: Voice, at: u64 = ASAP) {
    if !valid_voice(v) { return }
    lo, hi := schedule(at)
    args := [8]u32{lo, hi, 0, 0, 0, 0, 0, 0}
    t.emit(w.op_audio_note_off, {t.session, v.index}, args[:])
}
node_control :: proc(
    v: Voice,
    inst: Instrument,
    node: u32,
    parameter: Parameter,
    value: f32,
    at: u64 = ASAP,
    ramp_frames: u32 = 0,
) {
    if !valid_voice(v) || !t.check(t.Handle(inst), w.kindInstrument) { return }
    lo, hi := schedule(at)
    args := [8]u32 {
        lo,
        hi,
        t.Handle(inst).id,
        node,
        u32(parameter),
        transmute(u32)value,
        ramp_frames,
        0,
    }
    t.emit(w.op_audio_node_control, {t.session, v.index}, args[:])
}
effects :: proc(bus: Bus, nodes: []Node, at: u64 = ASAP) {
    if !ready() { return }
    id := bus_id(bus)
    lo, hi := schedule(at)
    bytes: [w.graphHeaderBytes + w.maxBusNodes * w.graphNodeBytes]u8
    graph: []u8
    if len(nodes) != 0 { graph = encode_graph(nodes, bytes[:], true) }
    args := [8]u32{lo, hi, 0, 0, 0, 0, 0, 0}
    t.emit(w.op_audio_effects, {t.session, id}, args[:], graph)
}
effect_control :: proc(
    bus: Bus,
    node: u32,
    parameter: Parameter,
    value: f32,
    at: u64 = ASAP,
    ramp_frames: u32 = 0,
) {
    if !ready() { return }
    id := bus_id(bus)
    lo, hi := schedule(at)
    args := [8]u32{lo, hi, 0, node, u32(parameter), transmute(u32)value, ramp_frames, 1}
    t.emit(w.op_audio_node_control, {t.session, id}, args[:])
}
destroy_wavetable :: proc(target: Wavetable) {if ready() {t.destroy(
            t.Handle(target),
            w.kindWavetable,
        )}}
destroy_instrument :: proc(target: Instrument) {if ready() {t.destroy(
            t.Handle(target),
            w.kindInstrument,
        )}}

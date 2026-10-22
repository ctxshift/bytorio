package audio

import a "../../../runtime/odin/audio"
import w "../../../runtime/odin/resource_protocol"
import data "../data"
import t "../resource"

ASAP :: u64(w.audioMaxExactFrame + 1)
COMPLETION_NATURAL :: w.audioReasonNatural
COMPLETION_STOPPED :: w.audioReasonStopped
COMPLETION_CANCELLED :: w.audioReasonCancelled
Bus :: distinct t.Handle
Stream :: distinct t.Handle
Voice :: struct {
    session, index: u32,
}
Optional_F32 :: union {
    f32,
}
Optional_Frame :: union {
    u64,
}
float_value :: proc(value: Optional_F32, fallback: f32) -> f32 {
    n, ok := value.(f32)
    return n if ok else fallback
}
frame_value :: proc(value: Optional_Frame) -> u64 {
    n, ok := value.(u64)
    return n if ok else ASAP
}
Bus_Desc :: struct {
    parent: Bus,
    gain:   Optional_F32,
}
Play_Options :: struct {
    at:                   Optional_Frame,
    rate, gain:           Optional_F32,
    pan:                  f32,
    loop:                 bool,
    loop_start, loop_end: u32,
    bus:                  Bus,
}
Stream_Options :: struct {
    at:   Optional_Frame,
    gain: Optional_F32,
    pan:  f32,
    bus:  Bus,
}
Ogg_Options :: struct {
    loop:                 bool,
    loop_start, loop_end: u32,
}
ogg_stream :: proc(content_id: u32, opts: Ogg_Options = {}) -> Stream {
    if !ready() || !t.valid(content_id != 0, "invalid Ogg content id") { return {} }
    handle := t.reserve(10, 0)
    args := [8]u32{content_id, u32(opts.loop), opts.loop_start, opts.loop_end, 0, 0, 0, 0}
    t.emit(w.op_audio_ogg_stream, handle, args[:])
    return Stream(handle)
}
Status :: struct {
    frame, late_events, underrun_frames, rejected_writes, completed, completion_overflow: u64,
    lead_frames, epoch, pending_events:                                                   u32,
}
Completion :: struct {
    voice, reason: u32,
    frame, serial: u64,
}
time :: proc() -> u64 { return t.tick * w.audioFramesPerTick }
ready :: proc() -> bool { return t.ready() && t.valid(t.phase != 2, "audio requires init/update") }
voice :: proc(index: u32) -> Voice {
    if !ready() || !t.valid(index < w.maxVoices, "voice index outside range") { return {} }
    return {t.session, index}
}
valid_voice :: proc(v: Voice) -> bool {
    return(
        ready() &&
        t.valid(v.session == t.session && v.index < w.maxVoices, "stale voice or invalid index") \
    )
}
master :: proc() -> Bus { return Bus(t.Handle{t.session, 0}) }
bus_id :: proc(b: Bus) -> u32 {
    h := t.Handle(b)
    if h.id == 0 {
        _ = t.valid(h.session == 0 || h.session == t.session, "stale master bus")
        return 0
    }
    if !t.check(h, 9) { return 0 }
    return h.id
}
bus :: proc(desc: Bus_Desc = {}) -> Bus {
    if !ready() { return {} }
    parent := bus_id(desc.parent)
    h := t.reserve(9, 0)
    fields := [8]u32{parent, transmute(u32)float_value(desc.gain, 1), 0, 0, 0, 0, 0, 0}
    t.emit(w.op_audio_bus, h, fields[:])
    return Bus(h)
}
stream :: proc() -> Stream {
    if !ready() { return {} }
    h := t.reserve(10, 0)
    args: [8]u32
    t.emit(w.op_audio_stream, h, args[:])
    return Stream(h)
}
schedule :: proc(at: u64) -> (u32, u32) {
    value := time() if at == ASAP else at
    _ = t.valid(
        value >= time() && value <= time() + w.audioHorizonFrames && value <= w.audioMaxExactFrame,
        "audio event outside scheduling horizon",
    )
    return u32(value), u32(value >> 32)
}
play_sample :: proc(v: Voice, source: Sample, opts: Play_Options = {}) {
    if !valid_voice(v) || !t.check(t.Handle(source), 2) { return }
    lo, hi := schedule(frame_value(opts.at))
    args := [8]u32 {
        lo,
        hi,
        t.Handle(source).id,
        bus_id(opts.bus),
        transmute(u32)float_value(opts.rate, 1),
        transmute(u32)float_value(opts.gain, 1),
        transmute(u32)opts.pan,
        u32(opts.loop),
    }
    loop := [2]u32{opts.loop_start, opts.loop_end}
    bytes: [8]u8
    a.put(bytes[:], 0, loop[0])
    a.put(bytes[:], 4, loop[1])
    t.emit(w.op_audio_play_sample, {t.session, v.index}, args[:], bytes[:])
}
play_stream :: proc(v: Voice, source: Stream, opts: Stream_Options = {}) {
    if !valid_voice(v) || !t.check(t.Handle(source), 10) { return }
    lo, hi := schedule(frame_value(opts.at))
    args := [8]u32 {
        lo,
        hi,
        t.Handle(source).id,
        bus_id(opts.bus),
        transmute(u32)float_value(opts.gain, 1),
        transmute(u32)opts.pan,
        0,
        0,
    }
    t.emit(w.op_audio_play_stream, {t.session, v.index}, args[:])
}
stop :: proc(v: Voice, at: u64 = ASAP) {
    if !valid_voice(v) { return }
    lo, hi := schedule(at)
    args := [8]u32{lo, hi, 0, 0, 0, 0, 0, 0}
    t.emit(w.op_audio_stop, {t.session, v.index}, args[:])
}
release :: proc(v: Voice, fade_frames: u32, at: u64 = ASAP) {
    if !valid_voice(v) { return }
    lo, hi := schedule(at)
    args := [8]u32{lo, hi, fade_frames, 0, 0, 0, 0, 0}
    t.emit(w.op_audio_release, {t.session, v.index}, args[:])
}
control :: proc(v: Voice, parameter: u32, value: f32, at: u64, ramp_frames: u32) {
    if !valid_voice(v) { return }
    lo, hi := schedule(at)
    args := [8]u32{lo, hi, parameter, transmute(u32)value, ramp_frames, 0, 0, 0}
    t.emit(w.op_audio_voice_control, {t.session, v.index}, args[:])
}
gain :: proc(v: Voice, value: f32, at: u64 = ASAP, ramp_frames: u32 = 0) {
    control(v, 0, value, at, ramp_frames)
}
pan :: proc(v: Voice, value: f32, at: u64 = ASAP, ramp_frames: u32 = 0) {
    control(v, 1, value, at, ramp_frames)
}
bus_gain :: proc(target: Bus, value: f32, at: u64 = ASAP, ramp_frames: u32 = 0) {
    if !ready() { return }
    id := bus_id(target)
    lo, hi := schedule(at)
    args := [8]u32{lo, hi, transmute(u32)value, ramp_frames, 0, 0, 0, 0}
    t.emit(w.op_audio_bus_gain, {t.session, id}, args[:])
}
write_stream :: proc(target: Stream, at: u64, pcm: data.PCM_Buffer) {
    if !ready() ||
       !t.check(t.Handle(target), 10) ||
       !t.valid(
               pcm.channels == 2 &&
               pcm.frames > 0 &&
               pcm.frames <= w.maxStreamFrames &&
               len(pcm.samples) == pcm.frames * 2,
               "stream requires bounded stereo PCM",
           ) { return }
    lo, hi := schedule(at)
    args := [8]u32{lo, hi, u32(pcm.frames), 0, 0, 0, 0, 0}
    bytes := (cast([^]u8)raw_data(pcm.samples))[:len(pcm.samples) * 4]
    t.emit(w.op_audio_stream_write, t.Handle(target), args[:], bytes)
}
destroy_bus :: proc(target: Bus) { if ready() { t.destroy(t.Handle(target), 9) } }
destroy_stream :: proc(target: Stream) { if ready() { t.destroy(t.Handle(target), 10) } }
status :: proc() -> Status {
    b := t.audio_status[:]
    return {
        frame               = a.wide(b, 0),
        lead_frames         = w.audioLeadFrames,
        epoch               = a.word(b, 12),
        late_events         = a.wide(b, 16),
        underrun_frames     = a.wide(b, 24),
        rejected_writes     = a.wide(b, 32),
        completed           = a.wide(b, 40),
        completion_overflow = a.wide(b, 48),
        pending_events      = a.word(b, 56),
    }
}
completions :: proc() -> ([w.audioMailboxCompletions]Completion, int) {
    b := t.audio_status[:]
    count := int(a.word(b, 60))
    result: [w.audioMailboxCompletions]Completion
    for i in 0 ..< count {
        at := 64 + i * 24
        result[i] = {a.word(b, at), a.word(b, at + 4), a.wide(b, at + 8), a.wide(b, at + 16)}
    }
    return result, count
}

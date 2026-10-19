package audio_test

import mixer "../../runtime/odin/audio"
import w "../../runtime/odin/resource_protocol"
import r "../../runtime/odin/resources"
import audio "../../sdk/odin/audio"
import data "../../sdk/odin/data"
import t "../../sdk/odin/resource"
import "base:runtime"
import "core:sync"
import "core:testing"

sdk_mutex: sync.Mutex

tiny :: proc(test: ^testing.T, rate: u32 = w.audioRate) -> ^mixer.Engine {
    e := mixer.create()
    testing.expect(test, e != nil)
    e.lead_remaining = 0
    tx, ok := mixer.begin(e)
    testing.expect(test, ok)
    pcm := [2]f32{-1, 1}
    bytes := (cast([^]u8)&pcm)[:size_of(pcm)]
    lease, page, copied := mixer.snapshot(&tx, bytes)
    testing.expect(test, copied)
    testing.expect(test, mixer.append(&tx, {
            op          = w.op_audio_play_sample,
            lease       = lease,
            page        = page,
            frames      = 2,
            channels    = 1,
            source_rate = rate,
            rate        = 1,
            gain        = 1,
            loop_end    = 2,
        }))
    mixer.publish(&tx)
    return e
}
@(test)
interpolation_blocks_pause_and_reclamation :: proc(test: ^testing.T) {
    e := tiny(test, 24000)
    defer mixer.close(e)
    output: [32]f32
    previous_allocator := context.allocator
    context.allocator.procedure = runtime.nil_allocator_proc
    mixer.render(e, output[:])
    context.allocator = previous_allocator
    expected := [4]f32{-1, 0, 1, 0}
    for value, i in output { testing.expect_value(test, value, expected[(i / 2) % 4]) }
    other := tiny(test, 24000)
    defer mixer.close(other)
    for i in 0 ..< 16 { mixer.render(other, output[i * 2:][:2]) }
    testing.expect_value(test, other.published_frame, e.published_frame)
    for value, i in output { testing.expect_value(test, value, expected[(i / 2) % 4]) }
    mixer.pause(e, true)
    fading: [w.audioPauseFadeFrames * 2]f32
    mixer.render(e, fading[:])
    frame := e.published_frame
    mixer.render(e, output[:])
    testing.expect_value(test, e.published_frame, frame)
    for value in output { testing.expect_value(test, value, f32(0)) }
    mixer.pause(e, false)
    resumed: [(w.audioLeadFrames + 128) * 2]f32
    mixer.render(e, resumed[:])
    testing.expect(test, e.published_frame > frame)
    testing.expect_value(test, e.epoch, u32(3))
    tx, ok := mixer.begin(e)
    testing.expect(test, ok)
    testing.expect(test, mixer.append(&tx, {op = w.op_audio_stop, at = e.published_frame}))
    mixer.publish(&tx)
    mixer.render(e, output[:])
    testing.expect(test, e.used > 0, "renderer must not reclaim producer pages")
    mixer.reclaim(e)
    testing.expect_value(test, e.used, u64(0))
    testing.expect(test, e.completion_head > e.completion_tail)
}
@(test)
queue_pressure_and_stable_order :: proc(test: ^testing.T) {
    e := mixer.create()
    defer mixer.close(e)
    for _ in 0 ..< w.maxAudioBatches {
        tx, ok := mixer.begin(e)
        testing.expect(test, ok)
        testing.expect(test, mixer.append(&tx, {op = w.op_audio_stop}))
        mixer.publish(&tx)
    }
    _, ok := mixer.begin(e)
    testing.expect(test, !ok, "bounded producer queue applies backpressure")
    output: [2]f32
    mixer.render(e, output[:])
    tx, available := mixer.begin(e)
    testing.expect(test, available)
    // The initial lead has not rendered DSP events yet.
    for _ in 0 ..< w.maxAudioEvents - w.maxAudioBatches {
        testing.expect(test, mixer.append(&tx, {op = w.op_audio_stop}))
    }
    testing.expect(
        test,
        !mixer.append(&tx, {op = w.op_audio_stop}),
        "global event bound includes queued and scheduled commands",
    )
    mixer.publish(&tx)
    e.lead_remaining = 0
    mixer.render(e, output[:])
    testing.expect_value(test, e.processed, u64(w.maxAudioEvents))
    testing.expect_value(test, e.event_count, 0)
}
commit :: proc(registry: ^r.Registry) -> bool {
    t.end()
    _ = t.commit()
    return r.submit(registry, t.packet[:int(t.packet_size())])
}
@(test)
atomic_audio_validation_and_snapshots :: proc(test: ^testing.T) {
    sync.mutex_lock(&sdk_mutex)
    defer sync.mutex_unlock(&sdk_mutex)
    registry: r.Registry
    defer r.close(&registry)
    testing.expect(test, r.reset(&registry, 42))
    testing.expect(test, t.configure(42))
    t.begin(0)
    pcm := data.pcm(4, 1)
    defer data.free_pcm(&pcm)
    for &v in pcm.samples { v = 0.5 }
    source := audio.sample({frames = 4, channels = 1, rate = w.audioRate}, pcm)
    audio.play_sample(audio.voice(0), source, {loop = true, loop_end = 4})
    // A bad later command must roll back both ordinary resources and audio leases.
    audio.bus_gain(audio.master(), transmute(f32)u32(0x7fc00000))
    testing.expect(test, !commit(&registry))
    testing.expect_value(test, registry.bytes, 0)
    testing.expect(test, registry.audio == nil, "first audio engine allocation rolls back")
    testing.expect(test, t.ack(1))
    testing.expect(test, r.reset(&registry, 43))
    testing.expect(test, t.configure(43))
    t.begin(0)
    source = audio.sample({frames = 4, channels = 1, rate = w.audioRate}, pcm)
    voice := audio.voice(0)
    audio.play_sample(voice, source, {loop = true, loop_end = 4})
    for &v in pcm.samples { v = -0.5 }
    audio.write(source, {0, 4}, pcm)
    audio.destroy(source)
    testing.expect(test, commit(&registry), registry.error)
    testing.expect(test, t.ack(1))
    registry.audio.lead_remaining = 0
    output: [16]f32
    mixer.render(registry.audio, output[:])
    for value in output { testing.expect_value(test, value, f32(0.5)) }
}
@(test)
stream_overlap_and_bus_limits :: proc(test: ^testing.T) {
    sync.mutex_lock(&sdk_mutex)
    defer sync.mutex_unlock(&sdk_mutex)
    registry: r.Registry
    defer r.close(&registry)
    testing.expect(test, r.reset(&registry, 50))
    testing.expect(test, t.configure(50))
    t.begin(0)
    stream := audio.stream()
    pcm := data.pcm(8, 2)
    defer data.free_pcm(&pcm)
    audio.write_stream(stream, 100, pcm)
    audio.write_stream(stream, 104, pcm)
    testing.expect(test, !commit(&registry), "overlapping stream intervals rejected atomically")
    testing.expect(test, registry.audio == nil, "audio allocation rolls back on overlap")
    testing.expect(test, t.ack(1))
    testing.expect(test, r.reset(&registry, 51))
    testing.expect(test, t.configure(51))
    t.begin(0)
    for _ in 0 ..< w.maxBuses { _ = audio.bus() }
    testing.expect(test, !commit(&registry), "master counts against bus limit")
    testing.expect_value(test, registry.bytes, 0)
    testing.expect(test, t.ack(1))
}

@(test)
snapshot_pressure_voice_bank_and_late_controls :: proc(test: ^testing.T) {
    e := mixer.create()
    defer mixer.close(e)
    e.lead_remaining = 0
    bytes := make([]u8, w.maxAudioSnapshotBytes)
    defer delete(bytes)
    tx, ok := mixer.begin(e)
    testing.expect(test, ok)
    lease, page, copied := mixer.snapshot(&tx, bytes)
    testing.expect(test, copied)
    testing.expect(test, mixer.append(&tx, {op = w.op_audio_stop, lease = lease, page = page}))
    _, _, copied = mixer.snapshot(&tx, bytes[:4])
    testing.expect(test, !copied, "fixed PCM arena rejects additional snapshots")
    mixer.abort(&tx)
    testing.expect_value(test, e.used, u64(0))

    source := [1]f32{0.125}
    pcm := (cast([^]u8)raw_data(source[:]))[:size_of(source)]
    output: [256]f32
    for _ in 0 ..< 5 {
        tx, ok = mixer.begin(e)
        testing.expect(test, ok)
        for i in 0 ..< w.maxVoices {
            lease, page, copied = mixer.snapshot(&tx, pcm)
            testing.expect(test, copied)
            testing.expect(test, mixer.append(&tx, {
                    op          = w.op_audio_play_sample,
                    id          = u32(i),
                    at          = e.frame,
                    lease       = lease,
                    page        = page,
                    frames      = 1,
                    channels    = 1,
                    source_rate = w.audioRate,
                    loop_end    = 1,
                    rate        = 1,
                    gain        = 1,
                }))
        }
        mixer.publish(&tx)
        mixer.render(e, output[:])
        // Device resampling may already hold two frames from the previous block.
        for value in output[4:] {
            testing.expect_value(test, value, f32(1))
        }
        tx, ok = mixer.begin(e)
        testing.expect(test, ok)
        for i in 0 ..< w.maxVoices {
            testing.expect(test, mixer.append(&tx, {op = w.op_audio_stop, id = u32(i)}))
        }
        mixer.publish(&tx)
        mixer.render(e, output[:])
        for value in output[4:] {
            testing.expect_value(test, value, f32(0))
        }
        mixer.reclaim(e)
        // Completion overflow must never prevent internal snapshot reclamation.
        testing.expect_value(test, e.used, u64(0))
    }
    testing.expect_value(test, e.completed, u64(5 * w.maxVoices))
    testing.expect_value(test, e.late, u64(5 * w.maxVoices))
    testing.expect_value(test, e.completion_overflow, u64(5 * w.maxVoices - w.maxAudioCompletions))
}

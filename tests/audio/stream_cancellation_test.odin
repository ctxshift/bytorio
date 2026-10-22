package audio_test

import mixer "../../runtime/odin/audio"
import w "../../runtime/odin/resource_protocol"
import "core:testing"

queued_pcm :: proc(
    test: ^testing.T,
    tx: ^mixer.Transaction,
    slot, resource: u32,
    at: u64,
    count: int,
    value: f32,
) -> u32 {
    pcm := make([]f32, count * 2)
    defer delete(pcm)
    for &sample in pcm { sample = value }
    lease, page, ok := mixer.snapshot(tx, (cast([^]u8)raw_data(pcm))[:len(pcm) * 4])
    testing.expect(test, ok)
    testing.expect(test, mixer.append(tx, {
            op       = w.op_audio_stream_write,
            id       = slot,
            resource = resource,
            at       = at,
            frames   = u32(count),
            channels = 2,
            lease    = lease,
            page     = page,
        }))
    return lease
}

@(test)
destroy_cancels_prefetched_pcm_before_stream_slot_reuse :: proc(test: ^testing.T) {
    engine := mixer.create()
    defer mixer.close(engine)
    engine.lead_remaining = 0
    initial, ok := mixer.begin(engine)
    testing.expect(test, ok)
    testing.expect(test, mixer.append(&initial, {op = w.op_audio_stream, id = 0, resource = 101}))
    testing.expect(test, mixer.append(&initial, {op = w.op_audio_stream, id = 1, resource = 202}))
    first := queued_pcm(test, &initial, 0, 101, 0, 8, 0.25)
    future := queued_pcm(test, &initial, 0, 101, 8, 8, 0.5)
    other := queued_pcm(test, &initial, 1, 202, 0, 16, 0.125)
    testing.expect(
        test,
        mixer.append(
            &initial,
            {op = w.op_audio_play_stream, id = 0, resource = 101, gain = 1, rate = 1},
        ),
    )
    testing.expect(
        test,
        mixer.append(
            &initial,
            {op = w.op_audio_play_stream, id = 1, resource = 202, gain = 1, rate = 1},
        ),
    )
    testing.expect(
        test,
        mixer.append(&initial, {op = w.op_audio_stream_end, id = 0, resource = 101, at = 16}),
    )
    testing.expect(
        test,
        mixer.append(&initial, {op = w.op_audio_stream_end, id = 1, resource = 202, at = 16}),
    )
    mixer.publish(&initial)

    replacement, next_ok := mixer.begin(engine)
    testing.expect(test, next_ok)
    testing.expect(
        test,
        mixer.append(&replacement, {op = w.op_audio_destroy, id = 0, resource = 101, at = 4}),
    )
    testing.expect(
        test,
        mixer.append(&replacement, {op = w.op_audio_stream, id = 0, resource = 303, at = 4}),
    )
    next := queued_pcm(test, &replacement, 0, 303, 4, 12, -0.25)
    testing.expect(
        test,
        mixer.append(
            &replacement,
            {op = w.op_audio_play_stream, id = 0, resource = 303, at = 4, gain = 1, rate = 1},
        ),
    )
    testing.expect(
        test,
        mixer.append(&replacement, {op = w.op_audio_stream_end, id = 0, resource = 303, at = 16}),
    )
    mixer.publish(&replacement)

    output: [32]f32
    mixer.render(engine, output[:8])
    for value in output[:8] { testing.expect_value(test, value, f32(0.375)) }
    // The renderer posts ownership releases; only the producer reclaims pages.
    testing.expect(test, engine.leases[first - 1].live && engine.leases[future - 1].live)
    mixer.reclaim(engine)
    testing.expect(test, !engine.leases[first - 1].live)
    testing.expect(
        test,
        !engine.leases[future - 1].live,
        "destroy promptly releases prefetched PCM",
    )
    testing.expect(test, engine.leases[other - 1].live && engine.leases[next - 1].live)
    mixer.render(engine, output[8:])
    for value in output[8:] { testing.expect_value(test, value, f32(-0.125)) }
    testing.expect_value(test, engine.rejected_writes, u64(0))
    testing.expect_value(test, engine.underruns, u64(0))
    testing.expect_value(test, engine.late, u64(0))
    testing.expect_value(test, engine.processed, engine.submitted)
    testing.expect_value(test, engine.event_count, 0)
    mixer.reclaim(engine)
    testing.expect_value(test, engine.used, u64(0))
    testing.expect_value(test, engine.completed, u64(3))
    // Four leases and three voice completions are released exactly once.
    testing.expect_value(test, engine.done_head, u32(7))
}

@(test)
aborted_stream_destroy_preserves_queued_pcm :: proc(test: ^testing.T) {
    engine := mixer.create()
    defer mixer.close(engine)
    engine.lead_remaining = 0
    initial, ok := mixer.begin(engine)
    testing.expect(test, ok)
    testing.expect(test, mixer.append(&initial, {op = w.op_audio_stream, id = 0, resource = 101}))
    _ = queued_pcm(test, &initial, 0, 101, 0, 4, 0.25)
    future := queued_pcm(test, &initial, 0, 101, 4, 4, 0.25)
    testing.expect(
        test,
        mixer.append(
            &initial,
            {op = w.op_audio_play_stream, id = 0, resource = 101, gain = 1, rate = 1},
        ),
    )
    testing.expect(
        test,
        mixer.append(&initial, {op = w.op_audio_stream_end, id = 0, resource = 101, at = 8}),
    )
    mixer.publish(&initial)
    aborted, next_ok := mixer.begin(engine)
    testing.expect(test, next_ok)
    testing.expect(
        test,
        mixer.append(&aborted, {op = w.op_audio_destroy, id = 0, resource = 101, at = 2}),
    )
    staged := queued_pcm(test, &aborted, 0, 303, 2, 4, -0.5)
    mixer.abort(&aborted)
    testing.expect(test, !engine.leases[staged - 1].live)
    testing.expect(test, engine.leases[future - 1].live)
    output: [16]f32
    mixer.render(engine, output[:])
    for value in output { testing.expect_value(test, value, f32(0.25)) }
    testing.expect_value(test, engine.rejected_writes, u64(0))
    mixer.reclaim(engine)
    testing.expect_value(test, engine.used, u64(0))
    testing.expect_value(test, engine.processed, engine.submitted)
}

@(test)
unowned_stream_write_still_reports_rejection :: proc(test: ^testing.T) {
    engine := mixer.create()
    defer mixer.close(engine)
    engine.lead_remaining = 0
    transaction, ok := mixer.begin(engine)
    testing.expect(test, ok)
    _ = queued_pcm(test, &transaction, 0, 999, 0, 4, 0.5)
    mixer.publish(&transaction)
    output: [8]f32
    mixer.render(engine, output[:])
    for value in output { testing.expect_value(test, value, f32(0)) }
    testing.expect_value(test, engine.rejected_writes, u64(1))
    mixer.reclaim(engine)
    testing.expect_value(test, engine.used, u64(0))
}

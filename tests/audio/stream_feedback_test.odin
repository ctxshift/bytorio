package audio_test

import mixer "../../runtime/odin/audio"
import w "../../runtime/odin/resource_protocol"
import "core:testing"

transfer_audio_batches :: proc(
    test: ^testing.T,
    producer, consumer: ^mixer.Engine,
    bytes: []u8,
) -> bool {
    for {
        count := mixer.export_batch(producer, bytes)
        if count == 0 { return true }
        if !testing.expect(test, count > 0) { return false }
        if !testing.expect(test, mixer.import_batch(consumer, bytes[:count])) { return false }
    }
}

@(test)
two_engine_cancellation_preserves_unique_pcm_leases_and_feedback :: proc(test: ^testing.T) {
    producer := mixer.create()
    consumer := mixer.create()
    defer mixer.close(producer)
    defer mixer.close(consumer)
    consumer.lead_remaining = 0
    packet := make([]u8, w.maxAudioPacketBytes)
    defer delete(packet)
    leases: [33]u32

    initial, ok := mixer.begin(producer)
    testing.expect(test, ok)
    testing.expect(test, mixer.append(&initial, {op = w.op_audio_stream, id = 0, resource = 101}))
    testing.expect(test, mixer.append(&initial, {op = w.op_audio_stream, id = 1, resource = 202}))
    // Deliberately publish valid chronological chunks in an interleaved order.
    // Destruction removes one stream while the other and its replacement remain.
    for index in 0 ..< 11 {
        chunk := (index * 7) % 11
        leases[index * 2] = queued_pcm(test, &initial, 0, 101, u64(chunk * 4), 4, 0.25)
        leases[index * 2 + 1] = queued_pcm(test, &initial, 1, 202, u64(chunk * 4), 4, 0.125)
    }
    for slot in 0 ..< 2 {
        resource := u32(101 if slot == 0 else 202)
        testing.expect(test, mixer.append(&initial, {
                op       = w.op_audio_play_stream,
                id       = u32(slot),
                resource = resource,
                gain     = 1,
                rate     = 1,
            }))
        testing.expect(
            test,
            mixer.append(
                &initial,
                {op = w.op_audio_stream_end, id = u32(slot), resource = resource, at = 44},
            ),
        )
    }
    mixer.publish(&initial)
    if !transfer_audio_batches(test, producer, consumer, packet) { return }

    replacement, next_ok := mixer.begin(producer)
    testing.expect(test, next_ok)
    testing.expect(
        test,
        mixer.append(
            &replacement,
            {op = w.op_audio_destroy, id = 0, resource = 101, parameter = 10, at = 3},
        ),
    )
    testing.expect(
        test,
        mixer.append(&replacement, {op = w.op_audio_stream, id = 0, resource = 303, at = 3}),
    )
    for index in 0 ..< 11 {
        leases[22 + index] = queued_pcm(test, &replacement, 0, 303, 3 + u64(index * 4), 4, -0.25)
    }
    testing.expect(
        test,
        mixer.append(
            &replacement,
            {op = w.op_audio_play_stream, id = 0, resource = 303, at = 3, gain = 1, rate = 1},
        ),
    )
    testing.expect(
        test,
        mixer.append(&replacement, {op = w.op_audio_stream_end, id = 0, resource = 303, at = 47}),
    )
    mixer.publish(&replacement)
    if !transfer_audio_batches(test, producer, consumer, packet) { return }

    output: [96]f32
    returned: [w.maxAudioLeases]bool
    released := 0
    for block in 0 ..< 12 {
        mixer.render(consumer, output[block * 8:][:8])
        bytes := mixer.feedback(consumer, packet)
        testing.expect(test, bytes >= 80)
        for index in 0 ..< int(mixer.word(packet, 8)) {
            lease := mixer.word(packet, 80 + index * 32)
            if lease == 0 { continue }
            if !testing.expect(
                test,
                !returned[lease - 1],
                "Each PCM lease completes exactly once across feedback packets",
            ) { return }
            returned[lease - 1] = true
            released += 1
        }
        if !testing.expect(
            test,
            mixer.import_feedback(producer, packet[:bytes]),
            "Producer accepts actual mixer feedback after cancellation",
        ) { return }
    }
    for value, sample in output {
        frame := sample / 2
        expected: f32 = 0
        if frame <
           3 { expected = 0.375 } else if frame < 44 { expected = -0.125 } else if frame < 47 { expected = -0.25 }
        testing.expect_value(test, value, expected)
    }
    testing.expect_value(test, released, 33)
    for lease in leases {
        testing.expect(test, returned[lease - 1])
        testing.expect(test, !producer.leases[lease - 1].live && !consumer.leases[lease - 1].live)
    }
    testing.expect_value(test, producer.processed, producer.submitted)
    testing.expect_value(test, consumer.processed, consumer.submitted)
    testing.expect_value(test, producer.used, u64(0))
    testing.expect_value(test, consumer.used, u64(0))
    testing.expect_value(test, producer.completed, u64(3))
    testing.expect_value(test, producer.rejected_writes, u64(0))
    testing.expect_value(test, producer.underruns, u64(0))
    testing.expect_value(test, producer.late, u64(0))
}

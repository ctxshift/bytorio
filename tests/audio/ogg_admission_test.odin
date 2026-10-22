package audio_test

import mixer "../../runtime/odin/audio"
import w "../../runtime/odin/resource_protocol"
import resources "../../runtime/odin/resources"
import audio "../../sdk/odin/audio"
import t "../../sdk/odin/resource"
import "core:sync"
import "core:testing"

@(test)
ogg_prefetch_reserves_update_batch_and_resumes_without_pcm_loss :: proc(test: ^testing.T) {
    sync.mutex_lock(&sdk_mutex)
    defer sync.mutex_unlock(&sdk_mutex)
    registry: resources.Registry
    defer resources.close(&registry)
    testing.expect(test, resources.reset(&registry, 76, w.oggProtocol))
    testing.expect(test, t.configure(76))
    t.begin(0)
    stream := audio.stream()
    audio.play_stream(audio.voice(0), stream)
    testing.expect(test, commit(&registry))
    testing.expect(test, t.ack(1))
    producer := registry.audio
    consumer := mixer.create()
    defer mixer.close(consumer)
    consumer.lead_remaining = 0
    packet := make([]u8, w.maxAudioPacketBytes)
    defer delete(packet)
    if !transfer_audio_batches(test, producer, consumer, packet) { return }
    testing.expect_value(test, mixer.producer_batches_available(producer), u32(w.maxAudioBatches))
    mixer.consume(consumer)

    // Model an already-open source decoder at the actual PCM admission seam.
    // Encoded Vorbis validation is covered separately; this test uses exact PCM.
    id := t.Handle(stream).id
    registry.ogg[0] = {
        id     = id,
        frames = w.maxStreamFrames,
    }
    pcm: [w.oggChunkFrames * 2]f32
    for &value in pcm { value = 0.25 }
    for index in 0 ..< w.maxAudioBatches - 1 {
        testing.expect(
            test,
            resources.ogg_feed(&registry, 0, id, u64(index * w.oggChunkFrames), pcm[:]),
        )
    }
    before := registry.ogg[0]
    testing.expect_value(test, mixer.producer_batches_available(producer), u32(1))
    before_head, before_submitted, before_bytes := producer.head, producer.submitted, producer.used
    if !testing.expect(
        test,
        !resources.ogg_feed(&registry, 0, id, before.next_frame, pcm[:]),
        "Ogg prefetch leaves one producer batch for the next game transaction",
    ) { return }
    testing.expect_value(test, registry.ogg[0], before)
    testing.expect_value(test, producer.head, before_head)
    testing.expect_value(test, producer.submitted, before_submitted)
    testing.expect_value(test, producer.used, before_bytes)

    t.begin(1)
    audio.bus_gain(audio.master(), 0.5)
    testing.expect(test, commit(&registry), "The reserved slot admits an ordinary game update")
    testing.expect(test, t.ack(2))
    testing.expect_value(test, mixer.producer_batches_available(producer), u32(0))
    _, overflow := mixer.begin(producer)
    testing.expect(
        test,
        !overflow,
        "A genuinely full batch queue still rejects another transaction",
    )
    if !transfer_audio_batches(test, producer, consumer, packet) { return }
    mixer.consume(consumer)
    testing.expect(test, resources.ogg_feed(&registry, 0, id, before.next_frame, pcm[:]))
    testing.expect_value(test, registry.ogg[0].cursor, u32(w.maxStreamFrames))
    testing.expect(test, registry.ogg[0].ended)
    if !transfer_audio_batches(test, producer, consumer, packet) { return }

    output := make([]f32, (w.maxStreamFrames + 4) * 2)
    defer delete(output)
    mixer.render(consumer, output)
    for value, index in output {
        frame := index / 2
        expected: f32 = 0
        if frame <
           w.audioFramesPerTick { expected = 0.25 } else if frame < w.maxStreamFrames { expected = 0.125 }
        testing.expect_value(test, value, expected)
    }
    feedback_bytes := mixer.feedback(consumer, packet)
    testing.expect(test, feedback_bytes >= 80)
    testing.expect(test, mixer.import_feedback(producer, packet[:feedback_bytes]))
    testing.expect_value(test, producer.processed, producer.submitted)
    testing.expect_value(test, producer.used, u64(0))
    testing.expect_value(test, consumer.used, u64(0))
    testing.expect_value(test, producer.completed, u64(1))
    testing.expect_value(test, producer.rejected_writes, u64(0))
    testing.expect_value(test, producer.underruns, u64(0))
    testing.expect_value(test, producer.late, u64(0))
}

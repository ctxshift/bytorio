package resources_test

import w "../../../runtime/odin/resource_protocol"
import r "../../../runtime/odin/resources"
import audio "../../../sdk/odin/audio"
import data "../../../sdk/odin/data"
import t "../../../sdk/odin/resource"
import "core:os"
import "core:testing"

ogg_packet :: proc() -> []u8 {
    t.end()
    _ = t.commit()
    return t.packet[:64 + int(t.count) * 32 + int(t.payload_size)]
}

@(test)
ogg_lifecycle :: proc(test: ^testing.T) {
    bytes, err := os.read_entire_file("tests/ogg/fixtures/tone.ogg", context.allocator)
    testing.expect(test, err == nil)
    if err != nil { return }
    defer delete(bytes)
    index: [12]u8
    r.put32(index[:], 0, 1)
    r.put32(index[:], 8, u32(len(bytes)))
    registry: r.Registry
    registry.content = {
        index = index[:],
        data  = bytes,
    }
    defer r.close(&registry)
    testing.expect(test, r.reset(&registry, 91))
    testing.expect(test, t.configure(91))
    t.begin(0)
    stream := audio.ogg_stream(1, {loop = true, loop_start = 431, loop_end = 4199})
    audio.play_stream(audio.voice(0), stream)
    packet := ogg_packet()
    saved := packet[96]
    packet[96] = 255
    testing.expect(test, !r.submit(&registry, packet))
    testing.expect_value(test, registry.ogg[0].id, u32(0))
    testing.expect_value(test, registry.bytes, 0)
    testing.expect(test, registry.audio == nil)
    packet[96] = saved
    testing.expect(test, r.submit(&registry, packet))
    testing.expect(test, t.ack(1))
    request := r.ogg_request(&registry, 0)
    testing.expect_value(test, request[0], t.Handle(stream).id)
    testing.expect_value(test, request[3], u32(24000))
    testing.expect_value(test, request[6], u32(w.oggChunkFrames))
    pcm := data.pcm(2, 2)
    defer data.free_pcm(&pcm)
    t.begin(1)
    audio.write_stream(stream, 800, pcm)
    testing.expect(
        test,
        !r.submit(&registry, ogg_packet()),
        "manual PCM cannot write an Ogg-owned queue",
    )
    // A rejected transaction is retryable and cannot move the source cursor.
    testing.expect_value(test, registry.ogg[0].cursor, u32(0))
    testing.expect(test, t.ack(2))
    testing.expect(test, t.configure(92))
    testing.expect(test, r.reset(&registry, 92))
    t.begin(0)
    stream = audio.ogg_stream(1)
    testing.expect(test, r.submit(&registry, ogg_packet()))
    testing.expect(test, t.ack(1))
    old_id := t.Handle(stream).id
    t.begin(1)
    audio.destroy_stream(stream)
    replacement := audio.ogg_stream(1)
    testing.expect(test, r.submit(&registry, ogg_packet()))
    testing.expect(test, t.ack(2))
    testing.expect(test, old_id != t.Handle(replacement).id)
    testing.expect(test, !r.ogg_feed(&registry, 0, old_id, 0, pcm.samples))
    testing.expect_value(test, registry.ogg[0].cursor, u32(0))
    r.put32(bytes, 40, 44100)
    _, valid := r.ogg_info(bytes)
    testing.expect(test, !valid, "unsupported source sample rate is rejected")
    _, valid = r.ogg_info(bytes[:20])
    testing.expect(test, !valid, "truncated container is rejected")
}

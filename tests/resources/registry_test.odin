package resources_test

import w "../../runtime/odin/resource_protocol"
import r "../../runtime/odin/resources"
import audio "../../sdk/odin/audio"
import data "../../sdk/odin/data"
import gfx "../../sdk/odin/gfx"
import t "../../sdk/odin/resource"
import "base:runtime"
import "core:testing"

@(test)
transactions :: proc(test: ^testing.T) {
    registry: r.Registry
    defer r.close(&registry)
    testing.expect(test, r.reset(&registry, 7))
    testing.expect(test, t.configure(7))
    t.begin(0)
    pixels := data.pixels(.RGBA8, 2, 2)
    defer data.free_pixels(&pixels)
    for &byte in pixels.bytes {

        byte = 255
    }
    texture := gfx.texture({.RGBA8, 2, 2})
    gfx.upload(texture, {0, 0, 2, 2}, pixels)
    pcm := data.pcm(4, 2)
    defer data.free_pcm(&pcm)
    pcm.samples[0] = 0.25
    pcm.samples[1] = -0.25
    sample := audio.sample({4, 2, 48000}, pcm)
    pixels.bytes[0] = 0
    pcm.samples[0] = 0
    t.end()
    testing.expect(test, t.commit() != 0)
    packet := t.packet[:64 + int(t.count) * 32 + int(t.payload_size)]
    allocator := context.allocator
    context.allocator = runtime.nil_allocator()
    rejected := !r.submit(&registry, packet)
    context.allocator = allocator
    testing.expect(test, rejected, "real allocator failure is reported before publication")
    testing.expect_value(test, registry.bytes, 0)
    testing.expect_value(test, registry.sequence, u32(0))
    testing.expect(test, r.submit(&registry, packet))
    testing.expect_value(test, registry.bytes, 48)
    testing.expect_value(test, registry.slots[0].data[0], u8(255))
    testing.expect_value(test, r.u32le(registry.slots[1].data, 0), transmute(u32)f32(0.25))
    testing.expect(test, !r.submit(&registry, packet), "replay is rejected")
    testing.expect(test, t.ack(1))
    baseline := r.hash(&registry)
    t.begin(1)
    gfx.upload(texture, {0, 0, 2, 2}, pixels)
    gfx.upload(texture, {0, 0, 2, 2}, pixels)
    t.end()
    _ = t.commit()
    packet = t.packet[:64 + int(t.count) * 32 + int(t.payload_size)]
    // A valid write followed by an invalid opcode must publish neither.
    r.put32(packet, 96, 999 | 32 << 16)
    testing.expect(test, !r.submit(&registry, packet))
    testing.expect_value(test, r.hash(&registry), baseline)
    r.put32(packet, 96, 3 | 32 << 16)
    testing.expect(
        test,
        !r.submit(&registry, packet, registry.bytes + len(packet)),
        "copy-on-write is charged",
    )
    testing.expect_value(test, r.hash(&registry), baseline)
    testing.expect(test, r.submit(&registry, packet))
    testing.expect(test, t.ack(2))
    t.begin(2)
    gfx.destroy(texture)
    audio.destroy(sample)
    replacement := gfx.texture({.Index8, 1, 1})
    t.end()
    _ = t.commit()
    packet = t.packet[:64 + int(t.count) * 32 + int(t.payload_size)]
    testing.expect(test, r.submit(&registry, packet))
    testing.expect_value(test, registry.bytes, 1)
    testing.expect_value(test, registry.slots[0].generation, u32(2))
    testing.expect(test, t.ack(3))
    t.begin(3)
    gfx.destroy(texture)
    testing.expect(test, t.error != "", "SDK rejects stale generation")
    t.end()
    t.error = ""
    // Wrong resource kind is rejected by the host even if a guest forges a command.
    t.begin(3)
    gfx.destroy(replacement)
    t.end()
    _ = t.commit()
    packet = t.packet[:64 + int(t.count) * 32 + int(t.payload_size)]
    r.put32(packet, 64, 6 | 32 << 16)
    testing.expect(test, !r.submit(&registry, packet))
    testing.expect_value(test, registry.bytes, 1)
    r.put32(packet, 64, 5 | 32 << 16)
    r.put32(packet, 12, 6)
    testing.expect(test, !r.submit(&registry, packet), "old session is rejected")
    r.put32(packet, 12, 7)
    testing.expect(test, r.submit(&registry, packet))
    testing.expect_value(test, registry.bytes, 0)
    testing.expect(test, t.ack(4))
    // Both registry and SDK retire a slot rather than wrapping its generation.
    registry.slots[0].generation = w.maxHandleGeneration
    t.slots[0].generation = w.maxHandleGeneration
    t.begin(4)
    last := gfx.texture({.Index8, 1, 1})
    gfx.destroy(last)
    next := gfx.texture({.Index8, 1, 1})
    t.end()
    _ = t.commit()
    packet = t.packet[:64 + int(t.count) * 32 + int(t.payload_size)]
    testing.expect(test, r.submit(&registry, packet))
    testing.expect_value(test, (t.Handle(next).id & w.handleIndexMask), u32(2))
    testing.expect_value(test, registry.slots[0].generation, u32(w.maxHandleGeneration + 1))
    testing.expect(test, t.ack(5))
    testing.expect(test, t.configure(8))
    t.begin(0)
    gfx.destroy(next)
    testing.expect(test, t.error != "", "SDK rejects a previous session handle")
    t.end()
    t.error = ""
}

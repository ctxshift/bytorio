package resources

import audio "../audio"
import w "../resource_protocol"
MAILBOX_MAGIC :: u32(w.mailboxMagic)
MAILBOX_HEADER :: w.mailboxPayloadOffset
MAILBOX_CAPACITY :: w.mailboxCapacity
LEGACY_MAILBOX_CAPACITY :: w.legacyMailboxCapacity

// Snapshot results were copied during draw. Delivery is deferred until a later
// update and bounded independently from the number of ready tickets.
mailbox :: proc(r: ^Registry, destination: []u8) -> int {
    header := MAILBOX_HEADER if r.protocol >= 3 else w.legacyMailboxPayloadOffset
    capacity := MAILBOX_CAPACITY if r.protocol >= 3 else LEGACY_MAILBOX_CAPACITY
    if len(destination) < capacity {

        return 0
    }
    for &byte in destination[:header] {

        byte = 0
    }
    if r.protocol >=
       3 { audio.write_status(r.audio, destination[w.audioStatusOffset:][:w.audioStatusBytes]) }
    count, payload := 0, 0
    for &slot, i in r.slots {
        if slot.kind != .Readback ||
           slot.delivered ||
           len(slot.data) > w.maxCompletionPayload - payload {

            continue
        }
        if count == w.mailboxMaxRecords {

            break
        }
        at := w.mailboxHeaderBytes + count * w.mailboxRecordBytes
        fields := [8]u32 {
            u32(i + 1) | slot.generation << w.handleIndexBits,
            slot.format,
            slot.width,
            slot.height,
            u32(header + payload),
            u32(len(slot.data)),
            0,
            0,
        }
        for field, index in fields {

            put32(destination, at + index * 4, field)
        }
        copy(destination[header + payload:][:len(slot.data)], slot.data)
        payload += len(slot.data)
        count += 1
        slot.delivered = true
    }
    put32(destination, 0, MAILBOX_MAGIC)
    put32(destination, 4, u32(count))
    put32(destination, 8, u32(header + payload))
    put32(destination, 12, r.session)
    return header + payload
}

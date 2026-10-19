package resource

import w "../../../runtime/odin/resource_protocol"
import r "../../../runtime/odin/resources"
import "base:runtime"
VERSION :: w.version

Handle :: struct {
    session, id: u32,
}
Local_Slot :: struct {
    generation, kind, format, channels: u32,
}
packet: [r.PACKET_BYTES]u8
slots: [w.maxSlots]Local_Slot
session, sequence, count, payload_size: u32
tick: u64
phase: u32
active, sealed: bool
active_pass, pass_serial, draw_epoch: u32
mailbox_size: u32
Result :: struct {
    format, width, height: u32,
    bytes:                 []u8,
    allocator:             runtime.Allocator,
}
results: [w.maxSlots]Result
error: string
fail :: proc(message: string) {

    if error == "" {

        error = message
    }
}
configure :: proc(value: u32) -> bool {
    if value == 0 || active || sealed {

        return false
    }
    session = value
    sequence = 0
    error = ""
    count = 0
    payload_size = 0
    when ODIN_ARCH == .wasm32 {

        context.allocator = runtime.default_wasm_allocator()
    }
    for &result in results {

        if len(result.bytes) > 0 {

            delete(result.bytes, result.allocator)
        }
        result = {}
    }
    active_pass = 0
    pass_serial = 0
    draw_epoch = 0
    mailbox_size = 0
    slots = {}
    for &slot in slots {

        slot.generation = 1
    }
    return true
}
begin :: proc(value: u64) {
    if sealed {

        fail("resource packet was not acknowledged")
        return
    }
    if value != 0 && mailbox_size != 0 {

        receive()
    }
    count = 0
    payload_size = 0
    tick = value
    phase = 0 if value == 0 else 1
    active = true
}
begin_draw :: proc(value: u64) {

    begin(value)
    phase = 2
    draw_epoch += 1
    active_pass = 0
}
end :: proc() {
    if phase == 2 && active_pass != 0 {

        fail("graphics pass was not ended")
    }
    active = false
}
valid :: proc(ok: bool, message: string) -> bool {
    if error != "" {

        return false
    }
    if !ok {

        fail(message)
        return false
    }
    return true
}
ready :: proc() -> bool {
    return valid(
        session != 0 && active && !sealed,
        "resource operations require a configured init/update callback",
    )
}
reserve :: proc(kind: u32, format: u32, channels: u32 = 0) -> Handle {
    if !ready() {

        return {}
    }
    if !valid(phase != 2 || kind == 8, "resource creation requires init/update") {

        return {}
    }
    for &slot, i in slots {

        if slot.kind == 0 && slot.generation <= w.maxHandleGeneration {

            slot.kind = kind
            slot.format = format
            slot.channels = channels
            return {session, u32(i + 1) | slot.generation << w.handleIndexBits}
        }
    }
    fail("resource slot capacity exceeded")
    return {}
}
check :: proc(handle: Handle, kind: u32) -> bool {
    if !ready() || !valid(handle.session == session, "stale resource session") {

        return false
    }
    if handle.id == 0 && kind == 3 {

        return true
    }
    index := handle.id & w.handleIndexMask
    if !valid(index > 0 && index <= w.maxSlots, "invalid resource slot") {

        return false
    }
    slot := slots[index - 1]
    return valid(
        (slot.kind == kind || (kind == 0 && slot.kind != 0)) &&
        slot.generation == handle.id >> w.handleIndexBits,
        "wrong resource kind or stale generation",
    )
}
emit :: proc(op: u32, handle: Handle, args: []u32 = nil, data: []u8 = nil) {
    if !ready() {

        return
    }
    needed := (payload_size + 3) &~ u32(3)
    if !valid(
        count < w.maxCommands && u64(needed) + u64(len(args) * 4) + u64(len(data)) <= w.maxPayload,
        "resource staging capacity exceeded",
    ) {

        return
    }
    args_at := needed
    data_at := args_at + u32(len(args) * 4)
    for value, i in args {

        r.put32(packet[:], r.PAYLOAD_OFFSET + int(args_at) + i * 4, value)
    }
    if len(data) > 0 {

        copy(packet[r.PAYLOAD_OFFSET + int(data_at):][:len(data)], data)
    }
    at := w.headerBytes + int(count) * w.commandBytes
    for &byte in packet[at:][:w.commandBytes] {

        byte = 0
    }
    packet[at] = u8(op)
    packet[at + 2] = w.commandBytes
    r.put32(packet[:], at + 8, handle.id)
    r.put32(packet[:], at + 12, args_at if len(args) > 0 else 0)
    r.put32(packet[:], at + 16, u32(len(args) * 4))
    r.put32(packet[:], at + 20, data_at if len(data) > 0 else 0)
    r.put32(packet[:], at + 24, u32(len(data)))
    count += 1
    payload_size = data_at + u32(len(data))
}
destroy :: proc(handle: Handle, kind: u32) {
    if !check(handle, kind) {

        return
    }
    if !valid(phase != 2, "resource destruction requires init/update") {

        return
    }
    emit(
        w.op_destroy_texture if kind == 1 else (w.op_destroy_sample if kind == 2 else w.op_destroy_resource),
        handle,
    )
    if kind == 8 {

        result := &results[(handle.id & w.handleIndexMask) - 1]
        if len(result.bytes) > 0 {

            delete(result.bytes, result.allocator)
        }
        result^ = {}
    }
    slot := &slots[(handle.id & w.handleIndexMask) - 1]
    slot.kind = 0
    slot.generation += 1
}
commit :: proc() -> u32 {
    if session == 0 {

        return 0
    }
    if error != "" || active || sealed || sequence == max(u32) {

        fail("cannot seal resource packet")
        return 0
    }
    sequence += 1
    for &byte in packet[:w.headerBytes] {

        byte = 0
    }
    payload_offset := u32(w.headerBytes) + count * w.commandBytes
    copy(
        packet[int(payload_offset):][:int(payload_size)],
        packet[r.PAYLOAD_OFFSET:][:int(payload_size)],
    )
    fields := [13]u32 {
        w.magic,
        w.abi,
        w.headerBytes,
        session,
        u32(tick),
        u32(tick >> 32),
        phase,
        sequence,
        count,
        w.headerBytes,
        count * w.commandBytes,
        payload_offset,
        payload_size,
    }
    for field, i in fields {

        r.put32(packet[:], i * 4, field)
    }
    sealed = true
    return u32(uintptr(&packet))
}
ack :: proc(value: u32) -> bool {
    if !sealed || value != sequence {

        fail("resource acknowledgement mismatch")
        return false
    }
    sealed = false
    return true
}
packet_size :: proc "contextless" () -> u32 {
    return w.headerBytes + count * w.commandBytes + payload_size
}
receive :: proc() {
    when ODIN_ARCH == .wasm32 {

        context.allocator = runtime.default_wasm_allocator()
    }
    bytes := packet[:int(mailbox_size)]
    if mailbox_size < 144 ||
       mailbox_size > r.MAILBOX_CAPACITY ||
       r.u32le(bytes, 0) != r.MAILBOX_MAGIC ||
       r.u32le(bytes, 4) > 4 ||
       r.u32le(bytes, 8) != mailbox_size ||
       r.u32le(bytes, 12) != session {

        fail("invalid resource mailbox")
        return
    }
    for i in 0 ..< int(r.u32le(bytes, 4)) {
        at := 16 + i * 32
        id := r.u32le(bytes, at)
        index := id & w.handleIndexMask
        offset, size := r.u32le(bytes, at + 16), r.u32le(bytes, at + 20)
        if index == 0 ||
           index > w.maxSlots ||
           slots[index - 1].kind != 8 ||
           slots[index - 1].generation != id >> w.handleIndexBits ||
           offset < 144 ||
           !r.within(offset, size, len(bytes)) {

            fail("invalid resource completion")
            return
        }
        result := &results[index - 1]
        if len(result.bytes) != 0 {

            fail("duplicate resource completion")
            return
        }
        data, err := make([]u8, int(size))
        if err != nil {

            fail("readback buffer allocation failed")
            return
        }
        copy(data, bytes[int(offset):][:int(size)])
        result^ = {
            r.u32le(bytes, at + 4),
            r.u32le(bytes, at + 8),
            r.u32le(bytes, at + 12),
            data,
            context.allocator,
        }
    }
    mailbox_size = 0
}

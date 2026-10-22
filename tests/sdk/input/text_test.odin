package input_test

import abi "../../../runtime/odin/abi"
import "core:testing"

@(test)
bounded_text_session :: proc(t: ^testing.T) {
    state: abi.Text_State
    packet := abi.Text_Packet {
        header = {
            version   = 1,
            id        = 7,
            flags     = 1,
            max_bytes = 8,
            length    = 3,
            start     = 1,
            end       = 3,
            x         = 1,
            y         = 2,
            width     = 100,
            height    = 20,
        },
    }
    copy(packet.bytes[:], "Aé")
    source := (cast(^[size_of(abi.Text_Packet)]u8)&packet)[:51]
    testing.expect(t, abi.text_configure(&state, source))
    packet.bytes[0] = 'Z'
    testing.expect(t, state.packet.bytes[0] == 'A', "host owns its snapshot")
    testing.expect(t, abi.text_replace(&state, transmute([]u8)string("🙂")))
    testing.expect_value(t, string(state.packet.bytes[:5]), "A🙂")
    before := state.packet
    testing.expect(
        t,
        !abi.text_replace(&state, transmute([]u8)string("🙂")),
        "whole edit rejected at byte cap",
    )
    testing.expect_value(t, state.packet.header.length, before.header.length)
    invalid := [2]u8{0xc0, 0xaf}
    testing.expect(t, !abi.text_replace(&state, invalid[:]), "overlong UTF-8 rejected")
    testing.expect(t, !abi.text_replace(&state, transmute([]u8)string("\n")), "single line only")
    destination: [size_of(abi.Text_Packet)]u8
    state.read_allowed = true
    testing.expect_value(t, abi.text_read(&state, destination[:48]), u32(0))
    testing.expect_value(t, abi.text_read(&state, destination[:]), u32(53))
    testing.expect_value(t, abi.text_read(&state, destination[:]), u32(0))
    state.read_allowed = true
    testing.expect_value(t, abi.text_read(&state, destination[:]), u32(53))
    testing.expect_value(t, state.packet.header.flags, u32(abi.TEXT_INPUT_ACTIVE))
    abi.text_backspace(&state)
    testing.expect_value(t, string(state.packet.bytes[:state.packet.header.length]), "A")
    abi.text_finish(&state, true)
    testing.expect(t, !abi.text_active(&state))
    testing.expect(t, state.packet.header.flags & abi.TEXT_INPUT_CANCELLED != 0)
    testing.expect(t, !abi.text_replace(&state, transmute([]u8)string("late")))
    packet = {
        header = {version = 1},
    }
    testing.expect(
        t,
        abi.text_configure(&state, (cast(^[size_of(abi.Text_Packet)]u8)&packet)[:48]),
    )
    testing.expect_value(t, state.packet.header.id, u32(0))
    packet.header.id = 1
    packet.header.flags = 1
    packet.header.max_bytes = 8
    packet.header.length = 3
    packet.header.start, packet.header.end = 2, 3
    packet.header.width, packet.header.height = 10, 10
    copy(packet.bytes[:], "Aé")
    testing.expect(t, !abi.text_configure(&state, source), "selection inside UTF-8 rejected")
    testing.expect(t, state.packet.header.id == 0, "rejected configure leaves closed session")
}

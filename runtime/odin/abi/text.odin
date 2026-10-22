package abi

import "core:unicode/utf8"

Text_Header :: struct {
    version, id, revision, flags:  u32,
    max_bytes, length, start, end: u32,
    x, y, width, height:           i32,
}
#assert(size_of(Text_Header) == TEXT_INPUT_HEADER_BYTES)

Text_Packet :: struct {
    header: Text_Header,
    bytes:  [TEXT_INPUT_MAX_BYTES]u8,
}

Text_State :: struct {
    packet:             Text_Packet,
    revision:           u32,
    read_allowed:       bool,
    composing:          bool,
    reversed_selection: bool,
}

text_active :: proc(state: ^Text_State) -> bool {
    return state.packet.header.flags & TEXT_INPUT_ACTIVE != 0
}

text_configure :: proc(state: ^Text_State, source: []u8) -> bool {
    if len(source) < TEXT_INPUT_HEADER_BYTES || len(source) > size_of(Text_Packet) {
        return false
    }
    packet: Text_Packet
    copy((cast(^[size_of(Text_Packet)]u8)&packet)[:], source)
    h := packet.header
    if h.version != TEXT_INPUT_VERSION { return false }
    if h.id == 0 {
        if len(source) != TEXT_INPUT_HEADER_BYTES { return false }
        for byte in source[TEXT_INPUT_FIELD_ID:] {
            if byte != 0 { return false }
        }
        state.revision += 1
        if state.revision == 0 { state.revision = 1 }
        state.packet = {}
        state.composing = false
        state.reversed_selection = false
        return true
    }
    if h.flags != TEXT_INPUT_ACTIVE ||
       h.revision != 0 ||
       len(source) != TEXT_INPUT_HEADER_BYTES + int(h.length) ||
       h.length > TEXT_INPUT_MAX_BYTES ||
       !text_valid(h, packet.bytes[:h.length]) ||
       !text_valid_rectangle(h) {
        return false
    }
    state.revision += 1
    if state.revision == 0 { state.revision = 1 }
    packet.header.revision = state.revision
    state.packet = packet
    state.composing = false
    state.reversed_selection = false
    return true
}

text_read :: proc(state: ^Text_State, destination: []u8) -> u32 {
    count := TEXT_INPUT_HEADER_BYTES + state.packet.header.length
    if !state.read_allowed ||
       state.packet.header.id == 0 ||
       len(destination) < int(count) { return 0 }
    copy(destination, (cast(^[size_of(Text_Packet)]u8)&state.packet)[:count])
    state.packet.header.flags &= TEXT_INPUT_ACTIVE
    state.read_allowed = false
    return count
}

text_replace :: proc(state: ^Text_State, inserted: []u8) -> bool {
    if !text_active(state) { return false }
    h := &state.packet.header
    if len(inserted) > int(h.max_bytes) { return false }
    length := h.length - (h.end - h.start) + u32(len(inserted))
    if length > h.max_bytes { return false }
    replacement := state.packet
    copy(replacement.bytes[h.start:], inserted)
    copy(replacement.bytes[int(h.start) + len(inserted):], state.packet.bytes[h.end:h.length])
    replacement.header.length = length
    replacement.header.start = h.start + u32(len(inserted))
    replacement.header.end = replacement.header.start
    if !text_valid(replacement.header, replacement.bytes[:length]) { return false }
    replacement.header.flags |= TEXT_INPUT_CHANGED
    state.packet = replacement
    state.reversed_selection = false
    return true
}

text_backspace :: proc(state: ^Text_State) {
    if !text_active(state) || state.composing { return }
    h := &state.packet.header
    if h.start == h.end {
        if h.start == 0 { return }
        h.start -= 1
        for h.start > 0 && state.packet.bytes[h.start] & 0xc0 == 0x80 {
            h.start -= 1
        }
    }
    _ = text_replace(state, nil)
}

text_finish :: proc(state: ^Text_State, cancelled: bool) {
    if !text_active(state) || state.composing { return }
    state.packet.header.flags &= ~u32(TEXT_INPUT_ACTIVE)
    state.packet.header.flags |= TEXT_INPUT_CANCELLED if cancelled else TEXT_INPUT_SUBMITTED
}

text_move :: proc(state: ^Text_State, right, extend, edge: bool) {
    if !text_active(state) || state.composing { return }
    h := &state.packet.header
    caret := h.start if state.reversed_selection else h.end
    anchor := h.end if state.reversed_selection else h.start
    if edge {
        caret = h.length if right else 0
    } else if !extend && h.start != h.end {
        caret = h.end if right else h.start
    } else if right && caret < h.length {
        caret += 1
        for caret < h.length && state.packet.bytes[caret] & 0xc0 == 0x80 { caret += 1 }
    } else if !right && caret > 0 {
        caret -= 1
        for caret > 0 && state.packet.bytes[caret] & 0xc0 == 0x80 { caret -= 1 }
    }
    if !extend { anchor = caret }
    h.start, h.end = min(anchor, caret), max(anchor, caret)
    state.reversed_selection = caret < anchor
    h.flags |= TEXT_INPUT_CHANGED
}

text_select_all :: proc(state: ^Text_State) {
    if !text_active(state) || state.composing { return }
    state.packet.header.start, state.packet.header.end = 0, state.packet.header.length
    state.reversed_selection = false
    state.packet.header.flags |= TEXT_INPUT_CHANGED
}

text_delete :: proc(state: ^Text_State) {
    if !text_active(state) || state.composing { return }
    h := &state.packet.header
    if h.start == h.end {
        if h.end == h.length { return }
        h.end += 1
        for h.end < h.length && state.packet.bytes[h.end] & 0xc0 == 0x80 { h.end += 1 }
    }
    _ = text_replace(state, nil)
}

text_boundary :: proc(value: []u8, offset: u32) -> bool {
    return offset <= u32(len(value)) && (offset == u32(len(value)) || value[offset] & 0xc0 != 0x80)
}

text_valid :: proc(header: Text_Header, value: []u8) -> bool {
    if header.version != TEXT_INPUT_VERSION ||
       header.max_bytes == 0 ||
       header.max_bytes > TEXT_INPUT_MAX_BYTES ||
       header.length != u32(len(value)) ||
       header.length > header.max_bytes ||
       header.start > header.end ||
       !text_boundary(value, header.start) ||
       !text_boundary(value, header.end) ||
       !utf8.valid_string(string(value)) {
        return false
    }
    for byte in value {
        if byte < 32 || byte == 127 { return false }
    }
    return true
}

text_valid_rectangle :: proc(header: Text_Header) -> bool {
    return(
        header.x >= COORDINATE_MIN &&
        header.x <= COORDINATE_MAX &&
        header.y >= COORDINATE_MIN &&
        header.y <= COORDINATE_MAX &&
        header.width > 0 &&
        header.width <= COORDINATE_MAX &&
        header.height > 0 &&
        header.height <= COORDINATE_MAX \
    )
}

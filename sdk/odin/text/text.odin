package text

import abi "../../../runtime/odin/abi"

MAX_BYTES :: abi.TEXT_INPUT_MAX_BYTES
VERSION :: abi.TEXT_INPUT_VERSION

Options :: struct {
    id:                             u32,
    value:                          string,
    max_bytes:                      u32,
    x, y, width, height:            i32,
    selection_start, selection_end: u32,
}

Event :: struct {
    id:                             u32,
    value:                          string,
    selection_start, selection_end: u32,
    changed, submitted, cancelled:  bool,
}

foreign import host "env"
foreign host {
    @(link_name = "text_configure")
    host_configure :: proc "c" (source: rawptr, length: u32) -> u32 ---
    @(link_name = "text_read")
    host_read :: proc "c" (destination: rawptr, capacity: u32) -> u32 ---
}

// Declare a field before the pointer gesture that will focus it on mobile.
configure :: proc(options: Options) -> bool {
    packet := abi.Text_Packet {
        header = {
            version   = abi.TEXT_INPUT_VERSION,
            id        = options.id,
            flags     = abi.TEXT_INPUT_ACTIVE,
            max_bytes = options.max_bytes,
            length    = u32(len(options.value)),
            start     = options.selection_start,
            end       = options.selection_end,
            x         = options.x,
            y         = options.y,
            width     = options.width,
            height    = options.height,
        },
    }
    if options.id == 0 ||
       !abi.text_valid(packet.header, transmute([]u8)options.value) ||
       !abi.text_valid_rectangle(packet.header) { return false }
    copy(packet.bytes[:], transmute([]u8)options.value)
    return host_configure(&packet, abi.TEXT_INPUT_HEADER_BYTES + packet.header.length) != 0
}

close :: proc() {
    header := abi.Text_Header {
        version = abi.TEXT_INPUT_VERSION,
    }
    _ = host_configure(&header, size_of(header))
}

// The returned value borrows destination until its next use. Events drain once.
read :: proc(destination: []u8) -> (Event, bool) {
    if len(destination) < MAX_BYTES { return {}, false }
    packet: abi.Text_Packet
    count := host_read(&packet, size_of(packet))
    if count < abi.TEXT_INPUT_HEADER_BYTES ||
       count > size_of(packet) ||
       !abi.text_valid(packet.header, packet.bytes[:count - abi.TEXT_INPUT_HEADER_BYTES]) {
        return {}, false
    }
    h := packet.header
    copy(destination, packet.bytes[:h.length])
    return {
            id              = h.id,
            value           = string(destination[:h.length]),
            selection_start = h.start,
            selection_end   = h.end,
            changed         = h.flags & abi.TEXT_INPUT_CHANGED != 0,
            submitted       = h.flags & abi.TEXT_INPUT_SUBMITTED != 0,
            cancelled       = h.flags & abi.TEXT_INPUT_CANCELLED != 0,
        }, true
}

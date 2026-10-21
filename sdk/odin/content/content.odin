package content

import abi "../../../runtime/odin/abi"

foreign import host "env"

foreign host {
    @(link_name = "content_size")
    host_size :: proc "c" (id: u32) -> u32 ---
    @(link_name = "content_read")
    host_read :: proc "c" (id, offset: u32, destination: rawptr, size: u32) -> u32 ---
}

// Zero means missing. Content entries are immutable and nonempty.
size :: proc(id: u32) -> u32 {
    return host_size(id)
}

// A rejected read leaves the whole destination unchanged.
read :: proc(id, offset: u32, destination: []u8) -> bool {
    if len(destination) > abi.MAX_CONTENT_READ_BYTES {
        return false
    }
    return host_read(id, offset, raw_data(destination), u32(len(destination))) == 1
}

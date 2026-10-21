package save

import abi "../../../runtime/odin/abi"

MAX_BYTES :: abi.MAX_SAVE_BYTES
VERSION :: abi.SAVE_VERSION
Status :: enum u32 {
    Empty   = abi.SAVE_EMPTY,
    Ready   = abi.SAVE_READY,
    Pending = abi.SAVE_PENDING,
    Error   = abi.SAVE_ERROR,
}

foreign import host "env"
foreign host {
    @(link_name = "save_size")
    size :: proc "c" () -> u32 ---
    @(link_name = "save_status")
    host_status :: proc "c" () -> u32 ---
    @(link_name = "save_read")
    host_read :: proc "c" (destination: rawptr, capacity: u32) -> u32 ---
    @(link_name = "save_write")
    host_write :: proc "c" (source: rawptr, length: u32) -> u32 ---
}

status :: proc() -> Status { return Status(host_status()) }
// Returns the complete stored length, or zero without touching the destination.
read :: proc(destination: []u8) -> u32 {
    if len(destination) > MAX_BYTES { return 0 }
    return host_read(raw_data(destination), u32(len(destination)))
}
// Native Ready is committed; browser Pending must be polled until Ready or Error.
write :: proc(source: []u8) -> Status {
    if len(source) == 0 || len(source) > MAX_BYTES { return .Error }
    return Status(host_write(raw_data(source), u32(len(source))))
}

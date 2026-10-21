package cartridge

import abi "../abi"

// The index is sorted by positive ID. Offsets are relative to the payload area.
// Views borrow the cartridge bytes and must not outlive them.
Content :: struct {
    index: []u8,
    data:  []u8,
}

parse_content :: proc(bytes: []u8) -> (content: Content, error: string) {
    if len(bytes) < abi.CONTENT_HEADER_BYTES ||
       len(bytes) > abi.MAX_CONTENT_BYTES ||
       le32(bytes[abi.CONTENT_HEADER_MAGIC:]) != abi.CONTENT_MAGIC ||
       le32(bytes[abi.CONTENT_HEADER_VERSION:]) != abi.CONTENT_VERSION {
        return {}, "invalid cartridge content header"
    }
    count := le32(bytes[abi.CONTENT_HEADER_COUNT:])
    index_end := u64(abi.CONTENT_HEADER_BYTES) + u64(count) * abi.CONTENT_RECORD_BYTES
    if count == 0 || count > abi.MAX_CONTENT_ENTRIES || index_end > u64(len(bytes)) {
        return {}, "invalid cartridge content index"
    }
    content.index = bytes[abi.CONTENT_HEADER_BYTES:int(index_end)]
    content.data = bytes[int(index_end):]
    previous_id: u32
    expected_offset: u64
    for i in 0 ..< int(count) {
        record := content.index[i * abi.CONTENT_RECORD_BYTES:]
        id := le32(record[abi.CONTENT_RECORD_ID:])
        offset := le32(record[abi.CONTENT_RECORD_OFFSET:])
        size := le32(record[abi.CONTENT_RECORD_LENGTH:])
        if id <= previous_id ||
           u64(offset) != expected_offset ||
           size == 0 ||
           u64(offset) + u64(size) > u64(len(content.data)) {
            return {}, "invalid cartridge content entry"
        }
        previous_id = id
        expected_offset += u64(size)
    }
    if expected_offset != u64(len(content.data)) {
        return {}, "unindexed cartridge content bytes"
    }
    return
}

content_blob :: proc(content: Content, id: u32) -> []u8 {
    low, high := 0, len(content.index) / abi.CONTENT_RECORD_BYTES
    for low < high {
        middle := low + (high - low) / 2
        record := content.index[middle * abi.CONTENT_RECORD_BYTES:]
        candidate := le32(record[abi.CONTENT_RECORD_ID:])
        if candidate < id {
            low = middle + 1
        } else if candidate > id {
            high = middle
        } else {
            offset := int(le32(record[abi.CONTENT_RECORD_OFFSET:]))
            size := int(le32(record[abi.CONTENT_RECORD_LENGTH:]))
            return content.data[offset:offset + size]
        }
    }
    return nil
}

content_read :: proc(content: Content, id, offset: u32, destination: []u8) -> bool {
    blob := content_blob(content, id)
    if len(blob) == 0 ||
       len(destination) > abi.MAX_CONTENT_READ_BYTES ||
       u64(offset) + u64(len(destination)) > u64(len(blob)) {
        return false
    }
    copy(destination, blob[int(offset):int(offset) + len(destination)])
    return true
}

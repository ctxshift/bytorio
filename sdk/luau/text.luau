--!strict
local host = require("./native")
local c = require("./constants")

export type Options = {
    id: number,
    value: string,
    max_bytes: number,
    x: number,
    y: number,
    width: number,
    height: number,
    selection_start: number?,
    selection_end: number?,
}

local function integer(value: number, minimum: number, maximum: number): boolean
    return value >= minimum and value <= maximum and value % 1 == 0
end

local function configure(options: Options): boolean
    local start = options.selection_start or #options.value
    local finish = options.selection_end or #options.value
    if
        #options.value > c.TEXT_INPUT_MAX_BYTES
        or not integer(options.id, 1, 0xffffffff)
        or not integer(options.max_bytes, 1, c.TEXT_INPUT_MAX_BYTES)
        or not integer(start, 0, #options.value)
        or not integer(finish, start, #options.value)
        or not integer(options.x, c.COORDINATE_MIN, c.COORDINATE_MAX)
        or not integer(options.y, c.COORDINATE_MIN, c.COORDINATE_MAX)
        or not integer(options.width, 1, c.COORDINATE_MAX)
        or not integer(options.height, 1, c.COORDINATE_MAX)
    then
        return false
    end
    local packet = buffer.create(c.TEXT_INPUT_HEADER_BYTES + #options.value)
    buffer.writeu32(packet, c.TEXT_INPUT_FIELD_VERSION, c.TEXT_INPUT_VERSION)
    buffer.writeu32(packet, c.TEXT_INPUT_FIELD_ID, options.id)
    buffer.writeu32(packet, c.TEXT_INPUT_FIELD_FLAGS, c.TEXT_INPUT_ACTIVE)
    buffer.writeu32(packet, c.TEXT_INPUT_FIELD_MAX_BYTES, options.max_bytes)
    buffer.writeu32(packet, c.TEXT_INPUT_FIELD_LENGTH, #options.value)
    buffer.writeu32(packet, c.TEXT_INPUT_FIELD_START, start)
    buffer.writeu32(packet, c.TEXT_INPUT_FIELD_END, finish)
    buffer.writei32(packet, c.TEXT_INPUT_FIELD_X, options.x)
    buffer.writei32(packet, c.TEXT_INPUT_FIELD_Y, options.y)
    buffer.writei32(packet, c.TEXT_INPUT_FIELD_WIDTH, options.width)
    buffer.writei32(packet, c.TEXT_INPUT_FIELD_HEIGHT, options.height)
    buffer.writestring(packet, c.TEXT_INPUT_HEADER_BYTES, options.value)
    return host.text_configure(packet) ~= 0
end

local function close()
    local packet = buffer.create(c.TEXT_INPUT_HEADER_BYTES)
    buffer.writeu32(packet, c.TEXT_INPUT_FIELD_VERSION, c.TEXT_INPUT_VERSION)
    host.text_configure(packet)
end

export type Event = {
    id: number,
    value: string,
    selection_start: number,
    selection_end: number,
    changed: boolean,
    submitted: boolean,
    cancelled: boolean,
}

local function read(): Event?
    local packet = buffer.create(c.TEXT_INPUT_HEADER_BYTES + c.TEXT_INPUT_MAX_BYTES)
    local count = host.text_read(packet)
    if count < c.TEXT_INPUT_HEADER_BYTES then
        return nil
    end
    local flags = buffer.readu32(packet, c.TEXT_INPUT_FIELD_FLAGS)
    return {
        id = buffer.readu32(packet, c.TEXT_INPUT_FIELD_ID),
        value = buffer.readstring(
            packet,
            c.TEXT_INPUT_HEADER_BYTES,
            buffer.readu32(packet, c.TEXT_INPUT_FIELD_LENGTH)
        ),
        selection_start = buffer.readu32(packet, c.TEXT_INPUT_FIELD_START),
        selection_end = buffer.readu32(packet, c.TEXT_INPUT_FIELD_END),
        changed = bit32.band(flags, c.TEXT_INPUT_CHANGED) ~= 0,
        submitted = bit32.band(flags, c.TEXT_INPUT_SUBMITTED) ~= 0,
        cancelled = bit32.band(flags, c.TEXT_INPUT_CANCELLED) ~= 0,
    }
end

return table.freeze({
    version = c.TEXT_INPUT_VERSION,
    max_bytes = c.TEXT_INPUT_MAX_BYTES,
    configure = configure,
    close = close,
    read = read,
})

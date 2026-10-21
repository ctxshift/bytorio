--!strict
local host = require("./native")
local c = require("./constants")

return table.freeze({
    version = c.SAVE_VERSION,
    max_bytes = c.MAX_SAVE_BYTES,
    empty = c.SAVE_EMPTY,
    ready = c.SAVE_READY,
    pending = c.SAVE_PENDING,
    error = c.SAVE_ERROR,
    size = host.save_size,
    read = host.save_read,
    write = host.save_write,
    status = host.save_status,
})

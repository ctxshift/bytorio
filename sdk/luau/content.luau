--!strict
local host = require("./native")

-- IDs are positive u32 values; a missing entry has size zero.
-- Reads are all-or-nothing and leave the destination unchanged on failure.
return table.freeze({
    size = host.content_size,
    read = host.content_read,
})

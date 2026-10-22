--!strict
local c = require("./constants")

type Options = { loop: boolean?, loop_start: number?, loop_end: number? }

local function descriptor(
    contentId: number,
    opts: Options?,
    integer: (number, number, number) -> number
): { number }
    local options: Options = opts or {}
    return {
        integer(contentId, 1, c.U32_MAX),
        if options.loop then 1 else 0,
        integer(options.loop_start or 0, 0, c.U32_MAX),
        integer(options.loop_end or 0, 0, c.U32_MAX),
    }
end

return { descriptor = descriptor }

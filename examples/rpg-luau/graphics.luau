-- Shared guest-side drawing helpers. Assets are bundled before this module.
local graphics = {}
local batched = console.draw_sprite ~= nil
if batched then console.graphics_assets(assets.raster64) end
function graphics.rect(x: number, y: number, w: number, h: number, color: number)
    console.rect(x, y, w, h, color)
end
function graphics.image(rows, x: number, y: number, scale: number?)
    local s = scale or 1
    for ry, row in rows do
        local col = 1
        while col <= #row do
            local ink = string.sub(row, col, col)
            local last = col + 1
            while last <= #row and string.sub(row, last, last) == ink do last += 1 end
            if ink ~= "." then
                local index = tonumber(ink, 16)
                graphics.rect(x+(col-1)*s, y+(ry-1)*s, (last-col)*s, s, assets.palette[index+1])
            end
            col = last
        end
    end
end
function graphics.sprite(id: number, x: number, y: number, scale: number?)
    if batched then console.draw_sprite(id,x,y,scale or 1); return end
    graphics.image(assets.sprites[id+1], x, y, scale)
end
function graphics.text(value: string, x: number, y: number, color: number)
    if batched then console.draw_text(value,x,y,color); return end
    local start = x
    for i = 1, #value do
        local c = string.sub(value, i, i)
        if c == "\n" then x = start; y += 9
        else
            local rows = assets.font[c]
            if rows then
                for ry, row in rows do
                    for col = 1, #row do
                        if string.sub(row, col, col) == "1" then graphics.rect(x+col-1,y+ry-1,1,1,color) end
                    end
                end
            end
            x += 6
        end
    end
end

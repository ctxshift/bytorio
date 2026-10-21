--!strict
local byt = require("@bytorio")
local course = require("./course")
local race = require("./race")
local scene = require("./scene")
local gfx = byt.gfx
local WHITE, INK, GOLD = 0xfff5f3ed, 0xff211b19, 0xff38d9ff

local function outlinedText(pass: byt.Pass, value: string, x: number, y: number, color: number?)
    for _, offset in { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } } do
        gfx.text(pass, value, x + offset[1], y + offset[2], INK)
    end
    gfx.text(pass, value, x, y, color or WHITE)
end

local function draw(pass: byt.Pass, s: race.State, high: boolean)
    local scale = if high then 2 else 1
    gfx.transform(pass, { scale, 0, 0, scale, 0, 0 })
    outlinedText(
        pass,
        string.format("LAP %d/3", math.min(3, math.floor(s.distance / 98304) + 1)),
        8,
        8
    )
    outlinedText(
        pass,
        string.format("%02d:%02d", math.floor(s.elapsed / 3600), math.floor(s.elapsed / 60) % 60),
        279,
        8
    )
    gfx.rect(pass, 148, 5, 24, 24, INK)
    gfx.rect(pass, 149, 6, 22, 22, WHITE)
    gfx.rect(pass, 151, 8, 18, 18, 0xff5a3318)
    if s.item ~= 0 then
        gfx.rect(pass, 159, 10, 5, 4, GOLD)
        gfx.rect(pass, 156, 14, 7, 4, GOLD)
        gfx.rect(pass, 159, 18, 4, 5, GOLD)
    end
    gfx.rect(pass, 8, 125, 58, 48, INK)
    gfx.rect(pass, 9, 126, 56, 46, WHITE)
    gfx.rect(pass, 11, 128, 52, 42, 0xff306538)
    for _, point in course do
        gfx.rect(pass, 36 + point[1] / 3, 149 + point[3] / 3, 2.2, 2.2, 0xffbab8b7)
    end
    for i, rival in s.rivals do
        local p = scene.sample(rival)
        gfx.rect(pass, 36 + p[1] / 3, 149 + p[3] / 3, 2, 2, scene.colors[i + 1])
    end
    local p = scene.sample(s.distance)
    gfx.rect(pass, 35 + p[1] / 3, 148 + p[3] / 3, 4, 4, INK)
    gfx.rect(pass, 36 + p[1] / 3, 149 + p[3] / 3, 2, 2, scene.colors[1])
    local position = race.rank(s)
    gfx.transform(pass, { scale * 3, 0, 0, scale * 3, 0, 0 })
    outlinedText(pass, tostring(position), 94, 50, GOLD)
    gfx.transform(pass, { scale, 0, 0, scale, 0, 0 })
    local suffix = if position == 1
        then "ST"
        elseif position == 2 then "ND"
        elseif position == 3 then "RD"
        else "TH"
    outlinedText(pass, suffix, 305, 164, GOLD)
    outlinedText(pass, string.format("%d KPH", math.floor(s.speed * 11 / 10)), 137, 164)
    if s.boost > 0 or s.drift ~= 0 then
        local color = if s.charge < 2 and s.boost == 0 then 0xffffcc58 else GOLD
        outlinedText(pass, if s.boost == 0 then "DRIFT" else "TURBO", 145, 150, color)
        gfx.rect(pass, 118, 176, 84, 2, INK)
        gfx.rect(pass, 119, 176, if s.boost == 0 then 40 * s.charge else 82, 1, color)
    end
    if s.tick <= 180 then
        gfx.transform(pass, { scale * 3, 0, 0, scale * 3, 0, 0 })
        outlinedText(pass, tostring(3 - math.min(2, math.floor(s.tick / 60))), 51, 22, GOLD)
        gfx.transform(pass, { scale, 0, 0, scale, 0, 0 })
    elseif s.tick < 225 then
        gfx.transform(pass, { scale * 2, 0, 0, scale * 2, 0, 0 })
        outlinedText(pass, "GO!", 72, 32, GOLD)
        gfx.transform(pass, { scale, 0, 0, scale, 0, 0 })
    end
    if s.finished ~= 0 then
        gfx.rect(pass, 62, 56, 196, 58, INK)
        outlinedText(pass, string.format("FINISH!  %d/8", position), 95, 69, GOLD)
        outlinedText(pass, "SPACE TO RACE AGAIN", 79, 96)
    elseif math.abs(s.lateral) > 680 then
        outlinedText(pass, "OFF ROAD", 136, 125, GOLD)
    end
end
return { draw = draw }

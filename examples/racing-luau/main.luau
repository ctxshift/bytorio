local byt = require("@bytorio")
local assets = require("./assets")
-- Copper Circuit: fixed-step simulation, integer projection and sprite billboards.
local LAP = 72000
local curves = { 0, 0, 1, 1, 0, -1, -1, 0, 1, 0, -1, 0 }
local s
local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local function clamp(x, lo, hi)
    return min(hi, max(lo, x))
end
local function curve(z)
    return curves[floor((z % LAP) / 6000) + 1]
end
local function init()
    byt.display(320, 180)
    s = {
        ticks = 0,
        distance = 0,
        x = 0,
        speed = 0,
        charge = 100,
        elapsed = 0,
        hits = 0,
        offroad = 0,
        boosts = 0,
        previous = false,
        finished = false,
        rivals = {},
        lanes = {},
    }
    for i = 0, 5 do
        s.rivals[i + 1] = -600 + i * 340
        s.lanes[i + 1] = (i % 3 - 1) * 420
    end
    byt.sound()
end
local function update()
    s.ticks += 1
    local held = byt.button("action")
    local action = held and not s.previous
    s.previous = held
    if s.finished then
        if action then
            init()
        end
        return
    end
    if s.ticks <= 90 then
        if s.ticks % 30 == 0 then
            byt.sound()
        end
        return
    end
    s.elapsed += 1
    if byt.button("up") then
        s.speed = if s.speed < 180 then min(180, s.speed + 3) else max(180, s.speed - 2)
    else
        s.speed = max(0, s.speed - 1)
    end
    if byt.button("down") then
        s.speed = max(0, s.speed - 6)
    end
    local boost = held and s.charge >= 2 and s.speed > 40
    if boost then
        s.speed = min(250, s.speed + 9)
        s.charge -= 2
        s.boosts += 1
    elseif s.ticks % 4 == 0 then
        s.charge = min(100, s.charge + 1)
    end
    local steering = 4 + floor(s.speed / 12)
    if byt.button("left") then
        s.x -= steering
    end
    if byt.button("right") then
        s.x += steering
    end
    s.x -= curve(s.distance) * floor(s.speed / 70)
    s.x = clamp(s.x, -1100, 1100)
    if abs(s.x) > 700 then
        s.speed = max(0, s.speed - 5)
        s.offroad += 1
    end
    local previousDistance = s.distance
    s.distance += s.speed
    for i = 0, 5 do
        local n = i + 1
        s.rivals[n] += min(144 + i * 6, s.elapsed * 3)
        s.lanes[n] = (i % 3 - 1) * 420 + abs((s.ticks + i * 37) % 240 - 120) - 60
        if
            abs(s.rivals[n] - s.distance) < 160
            and abs(s.lanes[n] - s.x) < 140
            and s.speed > 100
        then
            s.speed = 80
            s.hits += 1
            byt.sound()
            s.x += if s.x >= s.lanes[n] then 180 else -180
        end
    end
    if floor(s.distance / LAP) ~= floor(previousDistance / LAP) then
        byt.sound()
    end
    if s.distance >= LAP * 3 then
        s.finished = true
        byt.sound()
    end
end
local function rect(x, y, w, h, index)
    byt.rect(x, y, w, h, assets.palette[index + 1])
end
local function text(value, x, y, index)
    byt.text(value, x, y, assets.palette[index + 1])
end
local function sprite(id, x, y, scale)
    byt.sprite(id, x, y, scale or 1)
end
local function center(distance, p)
    local bend = floor(curve(s.distance + distance) * distance * distance * p / 2000000)
    return clamp(160 - floor(s.x * p / 1000) + bend, -100, 420)
end
local function billboard(id, distance, lane)
    if distance < 80 or distance > 5000 then
        return
    end
    local p = floor(7000 / (distance + 80))
    local size = clamp(floor(p * 3 / 4), 2, 48)
    byt.sprite_size(
        id,
        center(distance, p) + floor(lane * p / 1000) - floor(size / 2),
        48 + p - size,
        size,
        size
    )
end
local function draw()
    rect(0, 0, 320, 180, 0)
    rect(0, 18, 320, 56, 1)
    rect(248, 26, 20, 20, 10)
    for i = 0, 15 do
        rect(i * 22 - 10, 53 - abs(i % 6 - 3) * 3, 24, 24, 2)
    end
    sprite(6, 35, 28, 2)
    sprite(6, 160, 23, 2)
    for y = 49, 164 do
        local p = y - 48
        local distance = floor(7000 / p)
        local z = s.distance + distance
        local stripe = floor(z / 750) % 2
        rect(0, y, 320, 1, 3 + stripe)
        local half = floor(p * 17 / 10)
        local cx = center(distance, p)
        rect(cx - half - 5, y, half * 2 + 10, 1, if stripe == 0 then 12 else 11)
        rect(cx - half, y, half * 2, 1, 5 + stripe)
        if z % LAP < 350 then
            local tile = max(2, floor(p / 7))
            for x = cx - half, cx + half - 1, tile do
                rect(
                    x,
                    y,
                    min(tile, cx + half - x),
                    1,
                    if (floor((x - cx) / tile) + floor(z / 90)) % 2 == 0 then 11 else 0
                )
            end
        elseif z % 1500 < 700 then
            for _, side in { -1, 1 } do
                rect(
                    cx + floor(side * half / 3) - max(1, floor(p / 35)),
                    y,
                    max(1, floor(p / 18)),
                    1,
                    11
                )
            end
        end
    end
    for bucket = 12, 0, -1 do
        for i = 0, 5 do
            local distance = (s.rivals[i + 1] - s.distance) % LAP
            if floor(distance / 400) == bucket then
                billboard(1 + i % 3, distance, s.lanes[i + 1])
            end
        end
        for i = 0, 47 do
            local distance = (i * 1500 + LAP - s.distance % LAP) % LAP
            if floor(distance / 400) == bucket then
                billboard(4, distance, -1100)
                billboard(5, distance, 1100)
            end
        end
    end
    local kart = 0
    if byt.button("left") then
        kart = 7
    elseif byt.button("right") then
        kart = 8
    end
    if byt.button("action") and s.speed > 180 then
        rect(148, 153, 5, 10, 10)
        rect(166, 153, 5, 10, 12)
    end
    sprite(kart, 144, 129, 2)
    rect(0, 0, 320, 17, 0)
    rect(0, 17, 320, 1, 10)
    local rank = 1
    for _, rival in s.rivals do
        if rival > s.distance then
            rank += 1
        end
    end
    text("COPPER CIRCUIT", 5, 5, 11)
    text("LAP " .. min(3, floor(s.distance / LAP) + 1) .. "/3", 113, 5, 10)
    text("POS " .. rank .. "/7", 187, 5, 11)
    text(floor(s.elapsed / 60) .. " S", 272, 5, 11)
    rect(0, 165, 320, 15, 0)
    text(floor(s.speed * 14 / 10) .. " KPH", 5, 169, 11)
    text("BOOST", 100, 169, 10)
    rect(136, 168, 52, 9, 5)
    rect(137, 169, floor(s.charge / 2), 7, 10)
    text("UP: GAS  SPACE: BOOST", 195, 169, 11)
    rect(306, 27, 7, 126, 0)
    rect(309, 29, 1, 122, 11)
    for _, rival in s.rivals do
        rect(307, 29 + floor((rival % LAP) * 120 / LAP), 5, 2, 9)
    end
    rect(305, 29 + floor((s.distance % LAP) * 120 / LAP), 9, 3, 10)
    if s.ticks <= 90 then
        rect(119, 78, 82, 22, 0)
        text("READY " .. (3 - floor(s.ticks / 30)), 137, 85, 10)
    elseif s.finished then
        rect(39, 62, 242, 57, 0)
        rect(39, 62, 242, 2, 10)
        text("FINISH!  POSITION " .. rank, 65, 73, 10)
        text("TIME " .. floor(s.elapsed / 60) .. " SECONDS", 65, 87, 11)
        text("SPACE TO RACE AGAIN", 65, 102, 11)
    elseif abs(s.x) > 700 then
        text("OFF ROAD!", 130, 66, 12)
    end
end
return { init = init, update = update, draw = draw }

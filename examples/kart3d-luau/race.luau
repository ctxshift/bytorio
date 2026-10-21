--!strict
local course = require("./course")
local SEGMENT, SEGMENTS, LAP = 1024, 96, 98304
local ROAD_EDGE, WALL_EDGE = 680, 1150
local STEERING_RATE, DRIFT_STEERING_RATE = 18, 12

local function new()
    return {
        tick = 0,
        elapsed = 0,
        distance = 0,
        lateral = 0,
        heading = 0,
        speed = 0,
        drift = 0,
        charge = 0,
        switches = 0,
        last_steer = 0,
        switch_tick = 0,
        hop = 0,
        boost = 0,
        previous = 0,
        hits = 0,
        offroad = 0,
        boosts = 0,
        checkpoint = 0,
        finished = 0,
        item = 0,
        pickup = -1,
        events = 0,
        rivals = { 720, 1440, 2160, 2880, 3600, 4320, 5040 },
    }
end
export type State = typeof(new())
local function step(s: State, buttons: number)
    local pressed = bit32.band(buttons, bit32.bnot(s.previous))
    s.previous = buttons
    if bit32.band(pressed, 32768) ~= 0 or (s.finished ~= 0 and bit32.band(pressed, 16) ~= 0) then
        local reset = new()
        s.tick, s.elapsed, s.distance, s.lateral, s.heading, s.speed = 0, 0, 0, 0, 0, 0
        s.drift, s.charge, s.switches, s.last_steer, s.switch_tick, s.hop, s.boost =
            0, 0, 0, 0, 0, 0, 0
        s.previous, s.hits, s.offroad, s.boosts, s.checkpoint, s.finished = 0, 0, 0, 0, 0, 0
        s.item, s.pickup, s.events, s.rivals = 0, -1, 0, reset.rivals
        return
    end
    s.tick += 1
    local gas, brake, action =
        bit32.band(buttons, 4) ~= 0, bit32.band(buttons, 8) ~= 0, bit32.band(buttons, 16) ~= 0
    if s.tick <= 180 then
        if s.tick == 180 and s.boost > 0 then
            s.speed = 118
        end
        if s.tick % 60 == 0 then
            s.events += 1
        end
        if bit32.band(pressed, 4) ~= 0 and s.tick >= 120 and s.tick < 150 then
            s.boost = 28
        end
        if s.tick < 120 and gas then
            s.boost = 0
        end
        return
    end
    if s.finished ~= 0 then
        return
    end
    s.elapsed += 1
    local steer = (if bit32.band(buttons, 2) ~= 0 then 1 else 0)
        - (if bit32.band(buttons, 1) ~= 0 then 1 else 0)
    local curve = course[math.floor(s.distance / SEGMENT) % SEGMENTS + 1][6]
    if s.boost > 0 then
        s.boost -= 1
    end
    if s.hop > 0 then
        s.hop -= 1
    end
    local limit = if s.boost > 0 then 142 else 100
    if math.abs(s.lateral) > ROAD_EDGE then
        limit = 48
        s.offroad += 1
    end
    if brake then
        s.speed = math.max(0, s.speed - 5)
    elseif gas then
        s.speed += 1
    else
        s.speed = math.max(0, s.speed - 1)
    end
    if s.speed > limit then
        s.speed = math.max(limit, s.speed - 4)
    end
    if
        bit32.band(pressed, 16) ~= 0
        and steer ~= 0
        and s.speed >= 45
        and math.abs(s.lateral) < ROAD_EDGE
    then
        s.drift, s.charge, s.switches, s.last_steer = steer, 0, 0, steer
        s.hop, s.switch_tick = 12, s.tick
    end
    if s.drift ~= 0 then
        if not action or s.speed < 30 then
            if s.charge >= 2 then
                s.boost = 38
                s.boosts += 1
                s.events += 1
            end
            s.drift, s.charge = 0, 0
        elseif steer ~= 0 and steer ~= s.last_steer and s.tick - s.switch_tick >= 6 then
            s.switches += 1
            s.last_steer, s.switch_tick = steer, s.tick
            s.charge = math.min(2, math.floor(s.switches / 2))
        end
    end
    if bit32.band(pressed, 16384) ~= 0 and s.item ~= 0 then
        s.item, s.boost = 0, 50
        s.boosts += 1
        s.events += 1
    end
    s.heading += steer * (if s.drift ~= 0 then DRIFT_STEERING_RATE else STEERING_RATE) - math.floor(
        curve * s.speed / SEGMENT
    )
    if s.drift ~= 0 then
        s.heading += s.drift
    elseif s.heading > 0 then
        s.heading -= 1
    elseif s.heading < 0 then
        s.heading += 1
    end
    s.heading = math.clamp(s.heading, -150, 150)
    s.lateral += math.floor(s.heading * s.speed / 360)
    if math.abs(s.lateral) > WALL_EDGE then
        s.lateral = math.clamp(s.lateral, -WALL_EDGE, WALL_EDGE)
        s.heading = -math.floor(s.heading / 2)
        s.speed = math.floor(s.speed * 3 / 4)
        s.hits += 1
        s.events += 1
    end
    local old = s.distance
    s.distance += math.floor(s.speed * (1024 - math.abs(s.heading) * 2) / 1024)
    if math.floor(s.distance / (LAP / 4)) > math.floor(old / (LAP / 4)) then
        s.checkpoint += 1
    end
    local pickup = math.floor(s.distance / (SEGMENT * 12))
    if
        pickup ~= math.floor(old / (SEGMENT * 12))
        and math.abs(s.lateral) < ROAD_EDGE
        and pickup ~= s.pickup
    then
        s.item, s.pickup = 1, pickup
        s.events += 1
    end
    for i, rival in s.rivals do
        rival += 83 + (i - 1) * 2
        s.rivals[i] = rival
        local lane = ((i - 1) % 3 - 1) * 370
        if
            math.abs(rival - s.distance) < 120
            and math.abs(s.lateral - lane) < 200
            and s.tick % 18 == 0
        then
            s.speed = math.max(0, s.speed - 18)
            s.lateral += if s.lateral >= lane then 50 else -50
            s.hits += 1
            s.events += 1
        end
    end
    if s.checkpoint >= 12 then
        s.finished = 1
        s.events += 1
    end
end
local function rank(s: State): number
    local result = 1
    for _, rival in s.rivals do
        if rival > s.distance then
            result += 1
        end
    end
    return result
end
return { new = new, step = step, rank = rank }

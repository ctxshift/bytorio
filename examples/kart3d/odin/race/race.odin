package race

import course "../course"

SEGMENT :: 1024
SEGMENTS :: 96
LAP :: SEGMENT * SEGMENTS
LAPS :: 3
COUNTDOWN :: 180
ROAD_EDGE :: 680
WALL_EDGE :: 1150
TOP_SPEED :: 100
BOOST_SPEED :: 142
STEERING_RATE :: 18
DRIFT_STEERING_RATE :: 12

State :: struct {
    tick, elapsed, distance, lateral, heading, speed:                            int,
    drift, charge, switches, last_steer, switch_tick, hop, boost:                int,
    previous, hits, offroad, boosts, checkpoint, finished, item, pickup, events: int,
    rivals:                                                                      [7]int,
}

new :: proc() -> State {
    s := State {
        pickup = -1,
    }
    for &rival, i in s.rivals { rival = (i + 1) * 720 }
    return s
}

divide :: proc(a, b: int) -> int {
    q := a / b
    if a < 0 && a % b != 0 { q -= 1 }
    return q
}

step :: proc(s: ^State, buttons: int) {
    pressed := buttons &~ s.previous
    s.previous = buttons
    if pressed & 32768 != 0 || (s.finished != 0 && pressed & 16 != 0) {
        s^ = new()
        return
    }
    s.tick += 1
    if s.tick <= COUNTDOWN {
        if s.tick == COUNTDOWN && s.boost > 0 { s.speed = 118 }
        if s.tick % 60 == 0 { s.events += 1 }
        if pressed & 4 != 0 && s.tick >= 120 && s.tick < 150 { s.boost = 28 }
        if s.tick < 120 && buttons & 4 != 0 { s.boost = 0 }
        return
    }
    if s.finished != 0 { return }
    s.elapsed += 1
    steer := int(buttons & 2 != 0) - int(buttons & 1 != 0)
    curve := int(course.POINTS[(s.distance / SEGMENT) % SEGMENTS][5])
    if s.boost > 0 { s.boost -= 1 }
    if s.hop > 0 { s.hop -= 1 }
    limit := BOOST_SPEED if s.boost > 0 else TOP_SPEED
    if abs(s.lateral) > ROAD_EDGE {
        limit = 48
        s.offroad += 1
    }
    if buttons & 8 != 0 {
        s.speed = max(0, s.speed - 5)
    } else if buttons & 4 != 0 {
        s.speed += 1
    } else {
        s.speed = max(0, s.speed - 1)
    }
    if s.speed > limit { s.speed = max(limit, s.speed - 4) }
    if pressed & 16 != 0 && steer != 0 && s.speed >= 45 && abs(s.lateral) < ROAD_EDGE {
        s.drift, s.charge, s.switches, s.last_steer = steer, 0, 0, steer
        s.hop, s.switch_tick = 12, s.tick
    }
    if s.drift != 0 {
        if buttons & 16 == 0 || s.speed < 30 {
            if s.charge >= 2 {
                s.boost = 38
                s.boosts += 1
                s.events += 1
            }
            s.drift, s.charge = 0, 0
        } else if steer != 0 && steer != s.last_steer && s.tick - s.switch_tick >= 6 {
            s.switches += 1
            s.last_steer, s.switch_tick = steer, s.tick
            s.charge = min(2, s.switches / 2)
        }
    }
    if pressed & 16384 != 0 && s.item != 0 {
        s.item, s.boost = 0, 50
        s.boosts += 1
        s.events += 1
    }
    s.heading +=
        steer * (DRIFT_STEERING_RATE if s.drift != 0 else STEERING_RATE) -
        divide(curve * s.speed, SEGMENT)
    if s.drift != 0 {
        s.heading += s.drift
    } else if s.heading > 0 {
        s.heading -= 1
    } else if s.heading < 0 {
        s.heading += 1
    }
    s.heading = clamp(s.heading, -150, 150)
    s.lateral += divide(s.heading * s.speed, 360)
    if abs(s.lateral) > WALL_EDGE {
        s.lateral = clamp(s.lateral, -WALL_EDGE, WALL_EDGE)
        s.heading = -divide(s.heading, 2)
        s.speed = divide(s.speed * 3, 4)
        s.hits += 1
        s.events += 1
    }
    old := s.distance
    s.distance += divide(s.speed * (1024 - abs(s.heading) * 2), 1024)
    // Ordered progress cannot skip checkpoints: travel per tick is < one segment.
    if s.distance / (LAP / 4) > old / (LAP / 4) { s.checkpoint += 1 }
    pickup := s.distance / (SEGMENT * 12)
    if pickup != old / (SEGMENT * 12) && abs(s.lateral) < ROAD_EDGE && pickup != s.pickup {
        s.item, s.pickup = 1, pickup
        s.events += 1
    }
    for &rival, i in s.rivals {
        rival += 83 + i * 2
        separation := rival - s.distance
        lane := (i % 3 - 1) * 370
        if abs(separation) < 120 && abs(s.lateral - lane) < 200 && s.tick % 18 == 0 {
            s.speed = max(0, s.speed - 18)
            s.lateral += 50 if s.lateral >= lane else -50
            s.hits += 1
            s.events += 1
        }
    }
    if s.checkpoint >= LAPS * 4 {
        s.finished = 1
        s.events += 1
    }
}

rank :: proc(s: ^State) -> int {
    result := 1
    for rival in s.rivals { if rival > s.distance { result += 1 } }
    return result
}

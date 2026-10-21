package kart_test

import course "../../examples/kart3d-odin/course"
import race "../../examples/kart3d-odin/race"
import "core:testing"

@(test)
race_contract :: proc(t: ^testing.T) {
    s := race.new()
    for _ in 0 ..< 180 { race.step(&s, 4) }
    testing.expect_value(t, s.distance, 0)
    testing.expect_value(t, s.elapsed, 0)
    race.step(&s, 4)
    testing.expect_value(t, s.speed, 1)
    testing.expect_value(t, s.distance, 1)
    s = race.new()
    for _ in 0 ..< 125 { race.step(&s, 0) }
    for _ in 125 ..< 180 { race.step(&s, 4) }
    testing.expect_value(t, s.speed, 118)
    testing.expect_value(t, s.boost, 28)
    s = race.new()
    s.tick, s.speed = 200, 80
    race.step(&s, 4 | 2 | 16)
    testing.expect_value(t, s.drift, 1)
    testing.expect_value(t, s.hop, 12)
    for turn in 0 ..< 4 {
        for _ in 0 ..< 6 { race.step(&s, 4 | 16 | (1 if turn % 2 == 0 else 2)) }
    }
    testing.expect_value(t, s.charge, 2)
    race.step(&s, 4)
    testing.expect_value(t, s.boost, 38)
    testing.expect_value(t, s.boosts, 1)
    testing.expect_value(t, s.drift, 0)
    // Holding one steering direction never awards a charged release boost.
    s = race.new()
    s.tick, s.speed = 200, 80
    for _ in 0 ..< 15 { race.step(&s, 4 | 2 | 16) }
    race.step(&s, 4)
    testing.expect_value(t, s.boosts, 0)
    s = race.new()
    s.tick, s.speed, s.lateral = 200, 100, 900
    race.step(&s, 4)
    testing.expect_value(t, s.offroad, 1)
    testing.expect_value(t, s.speed, 97)
    s.lateral, s.heading = 1149, 150
    race.step(&s, 4 | 2)
    testing.expect(t, s.hits > 0)
    testing.expect(t, abs(s.lateral) <= race.WALL_EDGE)
    s = race.new()
    s.tick, s.distance, s.speed = 200, race.LAP / 4 - 10, 80
    race.step(&s, 4)
    testing.expect_value(t, s.checkpoint, 1)
    testing.expect_value(t, s.finished, 0)
    // Merely touching the lap line cannot finish a race with missing checkpoints.
    s.distance = 3 * race.LAP - 10
    race.step(&s, 4)
    testing.expect_value(t, s.finished, 0)
    s = race.new()
    s.tick, s.distance, s.speed = 200, 12 * race.SEGMENT - 10, 80
    race.step(&s, 4)
    testing.expect_value(t, s.item, 1)
    race.step(&s, 4 | 16384)
    testing.expect_value(t, s.item, 0)
    testing.expect_value(t, s.boost, 50)
    race.step(&s, 32768)
    testing.expect_value(t, s.tick, 0)
    testing.expect_value(t, s.distance, 0)
    testing.expect_value(t, s.rivals[6], 5040)
    // A scripted collision, independently of the full driving replay.
    s = race.new()
    s.tick, s.speed, s.lateral = 215, 80, -370
    s.rivals[0] = 0
    race.step(&s, 4)
    testing.expect_value(t, s.hits, 1)
    testing.expect_value(t, s.speed, 63)
    minimum, maximum := f64(100), f64(-100)
    for point in course.POINTS {
        minimum = min(minimum, point[1])
        maximum = max(maximum, point[1])
    }
    testing.expect(t, maximum - minimum > 4.9, "course includes real elevation")
}

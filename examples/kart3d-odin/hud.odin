package main

import course "./course"
import race "./race"
import gfx "sdk:gfx"

HUD_WHITE :: u32(0xfff5f3ed)
HUD_INK :: u32(0xff211b19)
HUD_GOLD :: u32(0xff38d9ff)

outlined_text :: proc(pass: gfx.Pass, value: string, x, y: f64, color := HUD_WHITE) {
    for offset in ([4][2]f64{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}) {
        gfx.text(pass, value, x + offset[0], y + offset[1], HUD_INK)
    }
    gfx.text(pass, value, x, y, color)
}

draw_hud :: proc(pass: gfx.Pass) {
    scale := f64(2 if high else 1)
    gfx.transform(pass, {scale, 0, 0, scale, 0, 0})
    outlined_text(pass, label("LAP %d/3", min(3, s.distance / race.LAP + 1)), 8, 8)
    outlined_text(pass, label("%02d:%02d", s.elapsed / 3600, (s.elapsed / 60) % 60), 279, 8)
    // The small inventory frame leaves the center of the road unobstructed.
    gfx.rect(pass, 148, 5, 24, 24, HUD_INK)
    gfx.rect(pass, 149, 6, 22, 22, HUD_WHITE)
    gfx.rect(pass, 151, 8, 18, 18, 0xff5a3318)
    if s.item != 0 {
        gfx.rect(pass, 159, 10, 5, 4, HUD_GOLD)
        gfx.rect(pass, 156, 14, 7, 4, HUD_GOLD)
        gfx.rect(pass, 159, 18, 4, 5, HUD_GOLD)
    }
    gfx.rect(pass, 8, 125, 58, 48, HUD_INK)
    gfx.rect(pass, 9, 126, 56, 46, HUD_WHITE)
    gfx.rect(pass, 11, 128, 52, 42, 0xff306538)
    for point in course.POINTS {
        gfx.rect(pass, 36 + point[0] / 3, 149 + point[2] / 3, 2.2, 2.2, 0xffbab8b7)
    }
    for rival, i in s.rivals {
        p, _ := sample(rival)
        gfx.rect(pass, 36 + p[0] / 3, 149 + p[2] / 3, 2, 2, KART_COLORS[i + 1])
    }
    p, _ := sample(s.distance)
    gfx.rect(pass, 35 + p[0] / 3, 148 + p[2] / 3, 4, 4, HUD_INK)
    gfx.rect(pass, 36 + p[0] / 3, 149 + p[2] / 3, 2, 2, KART_COLORS[0])
    position := race.rank(&s)
    gfx.transform(pass, {scale * 3, 0, 0, scale * 3, 0, 0})
    outlined_text(pass, label("%d", position), 94, 50, HUD_GOLD)
    gfx.transform(pass, {scale, 0, 0, scale, 0, 0})
    suffix := "TH"
    if position ==
       1 { suffix = "ST" } else if position == 2 { suffix = "ND" } else if position == 3 { suffix = "RD" }
    outlined_text(pass, suffix, 305, 164, HUD_GOLD)
    outlined_text(pass, label("%d KPH", s.speed * 11 / 10), 137, 164)
    if s.boost > 0 || s.drift != 0 {
        color := u32(0xffffcc58) if s.charge < 2 && s.boost == 0 else HUD_GOLD
        outlined_text(pass, "DRIFT" if s.boost == 0 else "TURBO", 145, 150, color)
        gfx.rect(pass, 118, 176, 84, 2, HUD_INK)
        gfx.rect(pass, 119, 176, 40 * f64(s.charge) if s.boost == 0 else 82, 1, color)
    }
    if s.tick <= race.COUNTDOWN {
        gfx.transform(pass, {scale * 3, 0, 0, scale * 3, 0, 0})
        outlined_text(pass, label("%d", 3 - min(2, s.tick / 60)), 51, 22, HUD_GOLD)
        gfx.transform(pass, {scale, 0, 0, scale, 0, 0})
    } else if s.tick < race.COUNTDOWN + 45 {
        gfx.transform(pass, {scale * 2, 0, 0, scale * 2, 0, 0})
        outlined_text(pass, "GO!", 72, 32, HUD_GOLD)
        gfx.transform(pass, {scale, 0, 0, scale, 0, 0})
    }
    if s.finished != 0 {
        gfx.rect(pass, 62, 56, 196, 58, HUD_INK)
        outlined_text(pass, label("FINISH!  %d/8", position), 95, 69, HUD_GOLD)
        outlined_text(pass, "SPACE TO RACE AGAIN", 79, 96)
    } else if abs(s.lateral) > race.ROAD_EDGE {
        outlined_text(pass, "OFF ROAD", 136, 125, HUD_GOLD)
    }
}

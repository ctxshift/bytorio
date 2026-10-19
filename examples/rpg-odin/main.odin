package main

import g "sdk:console"
import "assets"

Mode :: enum { Explore, Dialog, Battle }
State :: struct {
    x, y, hp, potions, enemy, choice, cooldown, steps: int,
    quest, herb, won, complete, defeated: bool,
    mode: Mode,
    message: string,
    previous, ticks: u32,
}
s: State

say :: proc(message: string) { s.mode = .Dialog; s.message = message; g.sound() }
near :: proc(x, y: int) -> bool { return abs(s.x-x)+abs(s.y-y) <= 1 }
tile :: proc(x, y: int) -> u8 {
    if x < 0 || x >= 32 || y < 0 || y >= 20 { return 'T' }
    return assets.world[y][x]
}
battle :: proc() {
    retaliation := 3
    switch s.choice {
    case 0: s.enemy -= 4; s.message = "YOU STRIKE FOR 4. SLIME HITS FOR 3."
    case 1: retaliation = 1; s.message = "YOU BRACE. SLIME HITS FOR 1."
    case 2:
        if s.potions == 0 { s.message = "NO POTIONS LEFT. CHOOSE ANOTHER ACTION."; return }
        s.potions -= 1
        s.hp = min(20,s.hp+8)
        s.message = "POTION RESTORES 8. SLIME HITS FOR 3."
    }
    g.sound()
    if s.enemy <= 0 {
        s.won = true
        say("THE SLIME RETREATS! THE GROVE IS SAFE.\nFIND THE GOLDEN SUNLEAF TO THE EAST.")
        return
    }
    s.hp = max(0,s.hp-retaliation)
    if s.hp == 0 {
        s.defeated = true
        say("YOU FALL... THE HEALER BRINGS YOU HOME.\nREST, THEN TRY THE GROVE AGAIN.")
    }
}
init :: proc() { s = State{x=5,y=6,hp=20,potions=1,enemy=10};g.sound() }
update :: proc(dt:f64) {
    buttons:=g.buttons()
    s.ticks += 1
    pressed := buttons & ~s.previous
    s.previous = buttons
    s.cooldown = max(0,s.cooldown-1)
    action := pressed & 16 != 0
    if s.mode == .Dialog {
        if action {
            s.mode = .Explore
            if s.defeated { s.x,s.y,s.hp,s.potions,s.enemy = 5,6,20,1,10; s.defeated = false }
        }
        return
    }
    if s.mode == .Battle {
        if pressed & 5 != 0 { s.choice = (s.choice+2)%3 }
        if pressed & 10 != 0 { s.choice = (s.choice+1)%3 }
        if action { battle() }
        return
    }
    if action {
        if near(5,4) {
            if s.herb && !s.complete {
                s.complete = true; s.hp = 20
                say("YOU BROUGHT THE SUNLEAF! THANK YOU.\nMOSSGLEN IS SAFE. QUEST COMPLETE!")
            } else if s.complete { say("THE GROVE IS QUIET AGAIN.\nTHANK YOU, FRIEND OF MOSSGLEN.")
            } else {
                s.quest = true
                say("A SLIME GUARDS THE SUNLEAF GROVE.\nCROSS THE EAST BRIDGE. BRING ONE HOME.")
            }
        } else if near(24,6) && !s.herb {
            if !s.quest { say("A GOLDEN SUNLEAF. SOMEONE MAY NEED IT.\nSPEAK TO THE HEALER IN MOSSGLEN FIRST.")
            } else if !s.won { say("THE SLIME KEEPS YOU FROM THE SUNLEAF.\nFACE IT IN THE GROVE FIRST.")
            } else { s.herb = true; say("YOU FOUND THE SUNLEAF!\nRETURN TO THE HEALER IN MOSSGLEN.") }
        } else { say("ARROWS OR WASD TO WALK. SPACE TO TALK.\nSEEK THE HEALER BESIDE THE RED HOUSE.") }
        return
    }
    dx, dy := 0, 0
    if buttons & 1 != 0 { dx = -1
    } else if buttons & 2 != 0 { dx = 1
    } else if buttons & 4 != 0 { dy = -1
    } else if buttons & 8 != 0 { dy = 1 }
    if dx == 0 && dy == 0 { s.cooldown = 0; return }
    if s.cooldown > 0 { return }
    s.cooldown = 8
    nx, ny := s.x+dx, s.y+dy
    t := tile(nx,ny)
    if t == 'W' || t == 'T' || t == 'R' || t == 'H' || (nx == 5 && ny == 4) { return }
    s.x,s.y = nx,ny
    s.steps += 1
    if nx == 19 && ny == 6 && !s.won {
        s.mode,s.enemy,s.choice = .Battle,10,0
        s.message = "A MOSS SLIME BLOCKS THE GROVE!"
        g.sound()
    }
}
draw :: proc() {
    g.debug_position(f64(s.x),f64(s.y))
    cx, cy := clamp(s.x-11,0,8)*16, clamp(s.y-4,0,10)*16
    for y in 0..<20 {
        for x in 0..<32 {
            sx, sy := x*16-cx, 24+y*16-cy
            if sx < 0 || sx >= 384 || sy < 24 || sy >= 184 { continue }
            id := 0
            switch tile(x,y) {
            case 'P': id = 1
            case 'W': id = 2
            case 'T': id = 3
            case 'R': id = 4
            case 'H': id = 5
            case 'F': id = 10
            case 'B': id = 11
            }
            sprite(id,sx,sy)
        }
    }
    actor(7,5,4,cx,cy)
    if !s.won { actor(9,19,6,cx,cy) }
    if !s.herb { actor(8,24,6,cx,cy) }
    actor(6 if s.steps%2 == 0 else 12,s.x,s.y,cx,cy)
    p := assets.palette
    g.rect(0,0,384,24,p[0]); g.rect(0,22,384,2,p[2])
    text("MOSSGLEN",8,8,p[14])
    text("HP",206,8,p[12]); text(number(s.hp),224,8,p[15]); text("/20",236,8,p[14])
    text("POTION",276,8,p[13]); text(number(s.potions),324,8,p[15])
    g.rect(0,184,384,32,p[0]); g.rect(0,184,384,2,p[2])
    objective := "TALK TO THE HEALER BY THE RED HOUSE"
    if s.complete { objective = "QUEST COMPLETE - THANK YOU FOR PLAYING"
    } else if s.herb { objective = "SUNLEAF FOUND - RETURN TO THE HEALER"
    } else if s.quest { objective = "CROSS THE EAST BRIDGE - FIND SUNLEAF" }
    text(objective,8,191,p[14]); text("ARROWS: WALK   SPACE: TALK / CONFIRM",8,203,p[9])
    if s.mode == .Dialog {
        g.rect(8,135,368,46,p[1]); g.rect(10,137,364,42,p[0])
        text(s.message,18,144,p[15]); text("SPACE >",312,166,p[13])
    } else if s.mode == .Battle {
        g.rect(0,24,384,160,p[0]); g.rect(0,96,384,88,p[2]); g.rect(0,96,384,3,p[3])
        sprite(6,58,66,3); sprite(9,261,55,4)
        text("TRAVELER",48,35,p[14]); text("MOSS SLIME",252,35,p[14])
        text("HP",264,124,p[15]); text(number(max(0,s.enemy)),284,124,p[15])
        g.rect(8,141,368,38,p[1]); text(s.message,16,149,p[15]); text("CHOOSE WITH ARROWS. SPACE TO CONFIRM.",16,164,p[13])
        g.rect(0,184,384,32,p[0])
        labels := [3]string{"ATTACK","GUARD","POTION"}
        for label, i in labels {
            x := 12+i*124
            if s.choice == i { g.rect(x,188,112,22,p[3]) }
            text(label,x+14,195,p[15])
        }
    }
}

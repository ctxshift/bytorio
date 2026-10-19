package main

import "core:fmt"
import "core:math"
import g "../../runtime/odin/graphics"
import "assets"

LAP :: 72000
curves := [12]int{0,0,1,1,0,-1,-1,0,1,0,-1,0}
State :: struct {
    ticks, sounds: u32,
    distance, x, speed, charge, elapsed, hits, offroad, boosts: int,
    previous: u32,
    finished: bool,
    rivals: [6]int,
    lanes: [6]int,
}
s: State
floor_div :: proc(a,b:int) -> int {return int(math.floor(f64(a)/f64(b)))}
curve :: proc(z:int) -> int {return curves[(z%LAP)/6000]}
init :: proc() {
    s = State{sounds=1,charge=100}
    for i in 0..<6 {s.rivals[i]=-600+i*340;s.lanes[i]=(i%3-1)*420}
}
update :: proc(buttons:u32) {
    s.ticks+=1
    action := buttons&16 != 0 && s.previous&16 == 0
    s.previous=buttons
    if s.finished {
        if action {sounds:=s.sounds;init();s.sounds=sounds+1}
        return
    }
    if s.ticks <= 90 {if s.ticks%30 == 0 {s.sounds+=1};return}
    s.elapsed+=1
    if buttons&4 != 0 {
        s.speed=min(180,s.speed+3) if s.speed<180 else max(180,s.speed-2)
    } else {s.speed=max(0,s.speed-1)}
    if buttons&8 != 0 {s.speed=max(0,s.speed-6)}
    boost := buttons&16 != 0 && s.charge >= 2 && s.speed > 40
    if boost {s.speed=min(250,s.speed+9);s.charge-=2;s.boosts+=1} else if s.ticks%4 == 0 {s.charge=min(100,s.charge+1)}
    steering := 4+s.speed/12
    if buttons&1 != 0 {s.x-=steering}
    if buttons&2 != 0 {s.x+=steering}
    s.x-=curve(s.distance)*(s.speed/70)
    s.x=clamp(s.x,-1100,1100)
    if abs(s.x)>700 {s.speed=max(0,s.speed-5);s.offroad+=1}
    previous_distance:=s.distance
    s.distance+=s.speed
    for i in 0..<6 {
        s.rivals[i]+=min(144+i*6,s.elapsed*3)
        s.lanes[i]=(i%3-1)*420+abs((int(s.ticks)+i*37)%240-120)-60
        if abs(s.rivals[i]-s.distance)<160 && abs(s.lanes[i]-s.x)<140 && s.speed>100 {
            s.speed=80;s.hits+=1;s.sounds+=1
            s.x+=180 if s.x>=s.lanes[i] else -180
        }
    }
    if s.distance/LAP != previous_distance/LAP {s.sounds+=1}
    if s.distance>=LAP*3 {s.finished=true;s.sounds+=1}
}
ink :: proc(index:int) -> u32 {return assets.palette[index]}
rect :: proc(x,y,w,h,index:int) {g.rect(x,y,w,h,ink(index))}
text :: proc(value:string,x,y,index:int) {g.text(value,x,y,ink(index))}
label_buffer: [128]u8
label :: proc(format:string,n:int) -> string {return fmt.bprintf(label_buffer[:],format,n)}
center :: proc(distance,p:int) -> int {
    bend:=floor_div(curve(s.distance+distance)*distance*distance*p,2000000)
    return clamp(160-floor_div(s.x*p,1000)+bend,-100,420)
}
billboard :: proc(id,distance,lane:int) {
    if distance<80 || distance>5000 {return}
    p:=7000/(distance+80)
    y:=48+p
    size:=clamp(p*3/4,2,48)
    x:=center(distance,p)+floor_div(lane*p,1000)-size/2
    g.sprite_size(id,x,y-size,size,size)
}
draw :: proc() {
    rect(0,0,320,180,0)
    rect(0,18,320,56,1)
    rect(248,26,20,20,10)
    // Distant ridges and clouds remain cheap batched primitives.
    for i in 0..<16 {rect(i*22-10,53-abs(i%6-3)*3,24,24,2)}
    g.sprite(6,35,28,2);g.sprite(6,160,23,2)
    for y in 49..<165 {
        p:=y-48
        distance:=7000/p
        z:=s.distance+distance
        stripe:=(z/750)%2
        rect(0,y,320,1,3+stripe)
        half:=p*17/10
        cx:=center(distance,p)
        rect(cx-half-5,y,half*2+10,1,12 if stripe==0 else 11)
        rect(cx-half,y,half*2,1,5+stripe)
        if z%LAP<350 {
            tile:=max(2,p/7)
            for x:=cx-half;x<cx+half;x+=tile {rect(x,y,min(tile,cx+half-x),1,11 if (floor_div(x-cx,tile)+(z/90))%2==0 else 0)}
        } else if z%1500<700 {
            sides:=[2]int{-1,1}
            for side in sides {rect(cx+floor_div(side*half,3)-max(1,p/35),y,max(1,p/18),1,11)}
        }
    }
    // Draw far-to-near so billboard overlap is deterministic.
    for bucket:=12;bucket>=0;bucket-=1 {
        for i in 0..<6 {
            distance:=(s.rivals[i]-s.distance)%LAP
            if distance<0 {distance+=LAP}
            if distance/400==bucket {billboard(1+i%3,distance,s.lanes[i])}
        }
        for i in 0..<48 {
            distance:=(i*1500+LAP-s.distance%LAP)%LAP
            if distance/400==bucket {billboard(4,distance,-1100);billboard(5,distance,1100)}
        }
    }
    kart:=0
    if s.previous&1 != 0 {kart=7} else if s.previous&2 != 0 {kart=8}
    if s.previous&16 != 0 && s.speed>180 {rect(148,153,5,10,10);rect(166,153,5,10,12)}
    g.sprite(kart,144,129,2)
    rect(0,0,320,17,0);rect(0,17,320,1,10)
    rank:=1
    for rival in s.rivals {if rival>s.distance {rank+=1}}
    text("COPPER CIRCUIT",5,5,11)
    text(label("LAP %d/3",min(3,s.distance/LAP+1)),113,5,10)
    text(label("POS %d/7",rank),187,5,11)
    text(label("%d S",s.elapsed/60),272,5,11)
    rect(0,165,320,15,0)
    text(label("%d KPH",s.speed*14/10),5,169,11)
    text("BOOST",100,169,10);rect(136,168,52,9,5);rect(137,169,s.charge/2,7,10)
    text("UP: GAS  SPACE: BOOST",195,169,11)
    // Track progress strip also shows rivals and completed laps.
    rect(306,27,7,126,0);rect(309,29,1,122,11)
    for rival in s.rivals {rect(307,29+((rival%LAP+LAP)%LAP)*120/LAP,5,2,9)}
    rect(305,29+(s.distance%LAP)*120/LAP,9,3,10)
    if s.ticks<=90 {
        rect(119,78,82,22,0);text(label("READY %d",3-int(s.ticks)/30),137,85,10)
    } else if s.finished {
        rect(39,62,242,57,0);rect(39,62,242,2,10)
        text(label("FINISH!  POSITION %d",rank),65,73,10)
        text(label("TIME %d SECONDS",s.elapsed/60),65,87,11)
        text("SPACE TO RACE AGAIN",65,102,11)
    } else if abs(s.x)>700 {text("OFF ROAD!",130,66,12)}
}

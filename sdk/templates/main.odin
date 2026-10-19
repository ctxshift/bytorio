package main
import "core:math"
import console "sdk:console"
x,y: f64
init :: proc() {x,y=40,40;console.sound()}
update :: proc(dt:f64) {
    if console.button(.Left) {x-=90*dt}
    if console.button(.Right) {x+=90*dt}
    if console.button(.Up) {y-=90*dt}
    if console.button(.Down) {y+=90*dt}
    active,px,py:=console.pointer()
    if active {x,y=px-8,py-8}
    w,h:=console.size()
    x,y=clamp(x,0,f64(w-16)),clamp(y,20,f64(h-16))
    if console.pressed(.Action) {console.sound()}
}
draw :: proc() {
    console.clear(console.rgb(23,32,46))
    console.sprite(0,int(x),int(y))
    console.text("HELLO, CONSOLE!",8,7,console.rgb(244,236,214))
}

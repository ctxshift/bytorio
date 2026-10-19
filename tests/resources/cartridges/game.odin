package main

import console "sdk:console"
import gfx "sdk:gfx"
import audio "sdk:audio"
import data "sdk:data"
image:gfx.Texture
sound:audio.Sample
pixels:data.Pixel_Buffer
pcm:data.PCM_Buffer
init :: proc() {
    scratch:=make([]u8,7)
    defer delete(scratch)
    assert(len(scratch)==7,"ordinary game allocations use the Wasm allocator")
    pixels=data.pixels(.RGBA8,2,2);pcm=data.pcm(4,2)
    for &byte in pixels.bytes {byte=255}
    pcm.samples[0]=0.25;pcm.samples[1]=-0.25
    image=gfx.texture({.RGBA8,2,2})
    gfx.upload(image,{0,0,2,2},pixels)
    sound=audio.sample({4,2,48000},pcm)
    for &byte in pixels.bytes {byte=0}
    for &value in pcm.samples {value=0}
}
update :: proc(_dt:f64) {
    if console.button(.Up) {gfx.destroy(image);gfx.upload(image,{0,0,2,2},pixels)}
    switch console.ticks() {
    case 2:
        for &byte in pixels.bytes {byte=128}
        gfx.upload(image,{0,0,2,2},pixels)
        for &byte in pixels.bytes {byte=0}
    case 3: audio.write(sound,{0,4},pcm)
    case 4: gfx.destroy(image);audio.destroy(sound)
    case 5: image=gfx.texture({.Index8,3,1})
    }
}
draw :: proc() {console.clear(console.rgb(16,24,32))}

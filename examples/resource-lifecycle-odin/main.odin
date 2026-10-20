package main

import audio "sdk:audio"
import console "sdk:console"
import data "sdk:data"
import gfx "sdk:gfx"

IMAGE_WIDTH :: 2
IMAGE_HEIGHT :: 2
SAMPLE_FRAMES :: 4
SAMPLE_CHANNELS :: 2
SAMPLE_RATE :: 48000

image: gfx.Texture
sound: audio.Sample
pixels: data.Pixel_Buffer
pcm: data.PCM_Buffer

fill_pixels :: proc(value: u8) {
    for &byte in pixels.bytes {
        byte = value
    }
}

upload_image :: proc() {
    gfx.upload(image, {0, 0, IMAGE_WIDTH, IMAGE_HEIGHT}, pixels)
}

init :: proc() {
    // This small allocation also exercises the cartridge's ordinary allocator.
    scratch := make([]u8, 7)
    defer delete(scratch)
    assert(len(scratch) == 7, "ordinary game allocations use the Wasm allocator")

    pixels = data.pixels(.RGBA8, IMAGE_WIDTH, IMAGE_HEIGHT)
    pcm = data.pcm(SAMPLE_FRAMES, SAMPLE_CHANNELS)
    fill_pixels(255)
    pcm.samples[0] = 0.25
    pcm.samples[1] = -0.25

    image = gfx.texture({.RGBA8, IMAGE_WIDTH, IMAGE_HEIGHT})
    upload_image()
    sound = audio.sample({SAMPLE_FRAMES, SAMPLE_CHANNELS, SAMPLE_RATE}, pcm)

    // Uploads snapshot their input. Reusing staging memory cannot change them.
    fill_pixels(0)
    for &value in pcm.samples {
        value = 0
    }
}

provoke_stale_handle_error :: proc() {
    // Deliberate negative fixture: the host must reject this whole transaction.
    gfx.destroy(image)
    upload_image()
}

update :: proc(_dt: f64) {
    if console.button(.Up) {
        provoke_stale_handle_error()
    }

    // Fixed ticks make this example a reproducible lifecycle conformance trace.
    switch console.ticks() {
    case 2:
        fill_pixels(128)
        upload_image()
        fill_pixels(0)
    case 3:
        audio.write(sound, {0, SAMPLE_FRAMES}, pcm)
    case 4:
        gfx.destroy(image)
        audio.destroy(sound)
    case 5:
        image = gfx.texture({.Index8, 3, 1})
    }
}

draw :: proc() {
    console.clear(console.rgb(16, 24, 32))
}

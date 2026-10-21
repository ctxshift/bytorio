package main

import byt "sdk:bytorio"
import data "sdk:data"
import gfx "sdk:gfx"
scene, indexed: gfx.Target
tex, full: gfx.Texture
palette: gfx.Palette
bands: gfx.Row_Table
mask, overlay, additive, table_pipe: gfx.Pipeline
ticket: gfx.Readback
rows: [180]gfx.Row
frame_pixels: data.Pixel_Buffer
bench: bool
init :: proc() {
    caps := byt.capabilities()
    assert(caps.profile == 2 && caps.abi == 2 && caps.sdk == 512)
    assert(caps.features == 7 && caps.protocol == 4)
    assert(caps.resource_bytes == 67108864 && caps.slots == 1024)
    assert(caps.payload_bytes == 1048576 && caps.audio_rate == 48000)
    assert(caps.audio_lead_frames == 2400)
    byt.display(.Low)
    stencil := gfx.target({format = .Stencil8, width = 320, height = 180})
    scene = gfx.target({format = .RGBA8, width = 320, height = 180, stencil = stencil})
    indexed = gfx.target({format = .Index8, width = 320, height = 180})
    pixels := data.pixels(.Index8, 2, 2)
    defer data.free_pixels(&pixels)
    initial := [4]u8{1, 2, 3, 0}
    for value, i in initial {

        pixels.bytes[i] = value
    }
    tex = gfx.texture({.Index8, 2, 2})
    gfx.upload(tex, {0, 0, 2, 2}, pixels)
    if len(frame_pixels.bytes) > 0 {

        data.free_pixels(&frame_pixels)
    }
    frame_pixels = data.pixels(.RGBA8, 640, 360)
    for &byte in frame_pixels.bytes {

        byte = 255
    }
    full = gfx.texture({.RGBA8, 640, 360})
    gfx.upload(full, {0, 0, 640, 360}, frame_pixels)
    colors: [256]u32
    colors[1] = gfx.rgba(255, 0, 0, 255)
    colors[2] = gfx.rgba(0, 255, 0, 255)
    colors[3] = gfx.rgba(0, 0, 255, 255)
    palette = gfx.palette(colors[:])
    colors[3] = gfx.rgba(255, 255, 0, 255)
    alternate := gfx.palette(colors[:])
    lut: [65536]u8
    for src in 0 ..< 256 {

        for dst in 0 ..< 256 {

            lut[src * 256 + dst] = u8((src + dst) % 256)
        }
    }
    table := gfx.color_table(lut[:])
    table_pipe = gfx.pipeline(
        {format = .Index8, blend = .Table, color_table = table, write_mask = u32(15)},
    )
    mask = gfx.pipeline(
        {format = .RGBA8, write_mask = u32(0), stencil = {reference = 1, replace_pass = true}},
    )
    overlay = gfx.pipeline({
            format = .RGBA8,
            blend = .Over,
            stencil = {compare = .Equal, reference = 1, write_mask = u32(0)},
        })
    additive = gfx.pipeline({format = .RGBA8, blend = .Add})
    bands = gfx.row_table(180)
    for &row, y in rows {

        row = {palette if y % 2 == 0 else alternate, i32(y % 3), 0}
    }
    gfx.write_rows(bands, 0, rows[:])
    ticket = {}
    bench = false
}
update :: proc(_dt: f64) {
    if ticket.id != 0 {
        result, ready := gfx.poll(ticket)
        if ready {

            assert(
                data.get_pixel(result, 0, 0) == gfx.rgba(133, 10, 15, 255),
                "readback lost submission version",
            )
            data.free_pixels(&result)
            ticket = {}
        }
    }
    bench = byt.button(.Down)
    if bench {
        byt.display(.High)
        for &byte in frame_pixels.bytes {

            byte = u8(byt.ticks() % 256)
        }
        gfx.upload(full, {0, 0, 640, 360}, frame_pixels)
        return
    }
    byt.display(.High if byt.ticks() >= 10 else .Low)
    if byt.ticks() == 10 {

        active, _, _ := byt.pointer()
        assert(!active, "mode switch changed the sampled pointer")
    }
    color := gfx.rgba(0, 0, (byt.ticks() * 13) % 256, 255)
    gfx.write(palette, 12, (cast([^]u8)&color)[:4])
    for &row, y in rows {

        row.x = i32((u32(y) + byt.ticks()) % 3)
    }
    gfx.write_rows(bands, 0, rows[:])
}
draw :: proc() {
    if bench {

        gfx.present(full)
        return
    }
    p := gfx.begin_pass(indexed, {clear = true, color = 1})
    gfx.bind(p, table_pipe)
    gfx.rect(p, 0, 0, 16, 16, 2)
    gfx.bind(p, gfx.default_pipeline(.Index8))
    gfx.draw(p, tex, {-1, -1, 4, 4}, {16, 0, 8, 8}, {flip_x = true, repeat_image = true})
    gfx.end_pass(p)
    p = gfx.begin_pass(
        scene,
        {clear = true, color = gfx.rgba(10, 20, 30, 255), clear_stencil = true},
    )
    gfx.bind(p, mask)
    gfx.rect(p, 10, 10, 40, 40, gfx.rgba(255, 255, 255, 255))
    gfx.bind(p, overlay)
    gfx.rect(p, 0, 0, 80, 80, gfx.rgba(255, 0, 0, 128))
    gfx.bind(p, gfx.default_pipeline(.RGBA8))
    gfx.clip(p, 20, 20, 2, 2)
    gfx.rect(p, 0, 0, 80, 80, gfx.rgba(0, 255, 0, 255))
    gfx.clip(p, 0, 0, 320, 180)
    gfx.transform(p, {0, 1, -1, 0, 60, 0})
    gfx.rect(p, 0, 0, 10, 10, gfx.rgba(0, 0, 255, 255))
    gfx.transform(p, {1, 0, 0, 1, 0, 0})
    gfx.draw(p, indexed, {0, 0, 24, 24}, {120, 0, 48, 48}, {palette = palette})
    gfx.bind(p, additive)
    gfx.rect(p, 80, 0, 8, 8, gfx.rgba(0, 0, 255, 64))
    gfx.bind(p, gfx.default_pipeline(.RGBA8))
    byt.sprite(0, 180, 20)
    byt.text("PASS", 180, 45, byt.rgb(255, 255, 255))
    if byt.button(.Up) {

        gfx.draw(p, scene, {0, 0, 1, 1}, {0, 0, 1, 1})
    }
    gfx.end_pass(p)
    if ticket.id == 0 {

        ticket = gfx.readback(scene, {10, 10, 2, 2})
    }
    p = gfx.begin_pass(scene)
    gfx.rect(p, 10, 10, 2, 2, gfx.rgba(0, 255, 0, 255))
    gfx.end_pass(p)
    if byt.ticks() % 8 >= 4 && byt.ticks() < 10 {

        gfx.present(indexed, {rows = bands, repeat_image = true})
    } else if byt.ticks() >= 10 {
        screen := gfx.screen()
        p = gfx.begin_pass(screen, {clear = true, color = byt.rgb(0, 0, 0)})
        gfx.draw(p, scene, {0, 0, 320, 180}, {0, 0, 640, 360})
        gfx.end_pass(p)
        gfx.present(screen)
    } else {

        gfx.present(scene)
    }
}

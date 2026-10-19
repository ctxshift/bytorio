package data

import w "../../../runtime/odin/resource_protocol"
import r "../../../runtime/odin/resources"
import transport "../resource"
import "base:runtime"
Pixel_Format :: enum u32 {
    Index8   = w.format_index8,
    RGBA8    = w.format_rgba8,
    Stencil8 = w.format_stencil8,
}
Pixel_Buffer :: struct {
    format:        Pixel_Format,
    width, height: int,
    bytes:         []u8,
    allocator:     runtime.Allocator,
}
PCM_Buffer :: struct {
    frames, channels: int,
    samples:          []f32,
    allocator:        runtime.Allocator,
}
pixels :: proc(format: Pixel_Format, width, height: int) -> Pixel_Buffer {
    when ODIN_ARCH == .wasm32 {

        if context.allocator.procedure == runtime.nil_allocator_proc {

            context.allocator = runtime.default_wasm_allocator()
        }
    }
    if !transport.valid(
        (format == .Index8 || format == .RGBA8 || format == .Stencil8) &&
        width >= 1 &&
        width <= w.maxImageAxis &&
        height >= 1 &&
        height <= w.maxImageAxis,
        "invalid pixel buffer descriptor",
    ) {

        return {}
    }
    bytes, err := make([]u8, width * height * (4 if format == .RGBA8 else 1))
    if err != nil {

        transport.fail("pixel buffer allocation failed")
        return {}
    }
    return {format, width, height, bytes, context.allocator}
}
pcm :: proc(frames, channels: int) -> PCM_Buffer {
    when ODIN_ARCH == .wasm32 {

        if context.allocator.procedure == runtime.nil_allocator_proc {

            context.allocator = runtime.default_wasm_allocator()
        }
    }
    if !transport.valid(
        frames >= 1 &&
        frames <= w.maxPayload / 4 &&
        (channels == 1 || channels == 2) &&
        u64(frames) * u64(channels) * 4 <= w.maxPayload,
        "invalid PCM buffer descriptor",
    ) {

        return {}
    }
    samples, err := make([]f32, frames * channels)
    if err != nil {

        transport.fail("PCM buffer allocation failed")
        return {}
    }
    return {frames, channels, samples, context.allocator}
}
free_pixels :: proc(buffer: ^Pixel_Buffer) {
    if len(buffer.bytes) > 0 {
        delete(buffer.bytes, buffer.allocator)
    }
    buffer^ = {}
}
free_pcm :: proc(buffer: ^PCM_Buffer) {
    if len(buffer.samples) > 0 {
        delete(buffer.samples, buffer.allocator)
    }
    buffer^ = {}
}
valid_pixels :: proc(buffer: Pixel_Buffer) -> bool {
    bpp := 4 if buffer.format == .RGBA8 else 1
    return transport.valid(
        (buffer.format == .RGBA8 || buffer.format == .Index8 || buffer.format == .Stencil8) &&
        buffer.width > 0 &&
        buffer.width <= 1024 &&
        buffer.height > 0 &&
        buffer.height <= 1024 &&
        len(buffer.bytes) == buffer.width * buffer.height * bpp,
        "invalid pixel buffer",
    )
}
get_pixel :: proc(buffer: Pixel_Buffer, x, y: int) -> u32 {
    if !valid_pixels(buffer) ||
       !transport.valid(
               x >= 0 && y >= 0 && x < buffer.width && y < buffer.height,
               "pixel outside buffer",
           ) {

        return 0
    }
    at := y * buffer.width + x
    return r.u32le(buffer.bytes, at * 4) if buffer.format == .RGBA8 else u32(buffer.bytes[at])
}
set_pixel :: proc(buffer: Pixel_Buffer, x, y: int, color: u32) {
    if !valid_pixels(buffer) ||
       !transport.valid(
               x >= 0 && y >= 0 && x < buffer.width && y < buffer.height,
               "pixel outside buffer",
           ) {

        return
    }
    if !transport.valid(
        r.premultiplied(color) if buffer.format == .RGBA8 else color <= 255,
        "invalid pixel value",
    ) {

        return
    }
    at := y * buffer.width + x
    if buffer.format == .RGBA8 {

        r.put32(buffer.bytes, at * 4, color)
    } else {

        buffer.bytes[at] = u8(color)
    }
}
fill_pixels :: proc(buffer: Pixel_Buffer, color: u32) {
    if !valid_pixels(buffer) ||
       !transport.valid(
               r.premultiplied(color) if buffer.format == .RGBA8 else color <= 255,
               "invalid fill value",
           ) {

        return
    }
    if buffer.format == .RGBA8 {

        for at := 0; at < len(buffer.bytes); at += 4 {

            r.put32(buffer.bytes, at, color)
        }
    } else {

        for &byte in buffer.bytes {

            byte = u8(color)
        }
    }
}
copy_pixels :: proc(
    destination: Pixel_Buffer,
    dx, dy: int,
    source: Pixel_Buffer,
    sx, sy, width, height: int,
) {
    if !valid_pixels(destination) || !valid_pixels(source) {

        return
    }
    if !transport.valid(
        destination.format == source.format &&
        min(dx, dy, sx, sy, width, height) >= 0 &&
        max(dx, dy, sx, sy, width, height) <= 1024 &&
        dx + width <= destination.width &&
        dy + height <= destination.height &&
        sx + width <= source.width &&
        sy + height <= source.height,
        "invalid pixel copy",
    ) {

        return
    }
    bpp := 4 if source.format == .RGBA8 else 1
    backwards :=
        uintptr(raw_data(destination.bytes)) + uintptr((dy * destination.width + dx) * bpp) >
        uintptr(raw_data(source.bytes)) + uintptr((sy * source.width + sx) * bpp)
    for i in 0 ..< height {
        row := height - 1 - i if backwards else i
        copy(
            destination.bytes[((dy + row) * destination.width + dx) * bpp:][:width * bpp],
            source.bytes[((sy + row) * source.width + sx) * bpp:][:width * bpp],
        )
    }
}

from_i16 :: proc(samples: []i16, channels: int) -> PCM_Buffer {
    if !transport.valid(
        (channels == 1 || channels == 2) && len(samples) > 0 && len(samples) % channels == 0,
        "invalid i16 PCM",
    ) { return {} }
    result := pcm(len(samples) / channels, channels)
    for value, i in samples { result.samples[i] = f32(value) / 32768 }
    return result
}

package resources

import w "../resource_protocol"
import "core:mem"

// Optional host quality device. The ordinary CPU reference allocates none of
// this storage. One player owns a device per native process or Wasm instance.
Software_Device :: struct {
    registry:               Registry,
    color, depth:           []u8,
    width, height, quality: int,
}

software_device: ^Software_Device
software_quality: int

software_configure :: proc(quality: int) {
    software_quality = quality
}

software_close :: proc() {
    if software_device == nil { return }
    delete(software_device.color)
    delete(software_device.depth)
    free(software_device)
    software_device = nil
}

software_storage_bytes :: proc "contextless" () -> int {
    if software_device == nil { return 0 }
    return len(software_device.color) + len(software_device.depth) + size_of(Software_Device)
}

software_encode :: proc(value: f64, alpha: f64) -> u32 {
    // Midpoint thresholds perform the inverse sRGB lookup without per-pixel pow.
    lo, hi := 0, 255
    for lo < hi {
        mid := (lo + hi) / 2
        if value >= SOFTWARE_SRGB_THRESHOLDS[mid] { lo = mid + 1 } else { hi = mid }
    }
    if alpha == 1 { return u32(lo) }
    // Interpolate the inverse transfer function for premultiplied edge pixels.
    lower := max(0, lo - 1)
    upper := min(255, lo + 1)
    encoded := f64(lower)
    if upper != lower {
        encoded +=
            clamp(
                (value - SOFTWARE_SRGB_DECODE[lower]) /
                (SOFTWARE_SRGB_DECODE[upper] - SOFTWARE_SRGB_DECODE[lower]),
                0,
                1,
            ) *
            f64(upper - lower)
    }
    return u32(clamp(pixel_round(encoded * alpha), 0, 255))
}

software_resolve :: proc(device: ^Software_Device, x, y, width, factor: int) -> (u32, f64) {
    first := u32le(device.color, (y * factor * width + x * factor) * 4)
    same := true
    nearest := 1.0
    for dy in 0 ..< factor {
        for dx in 0 ..< factor {
            at := (((y * factor + dy) * width) + x * factor + dx) * 4
            same = same && u32le(device.color, at) == first
            nearest = min(nearest, f32le(device.depth, at))
        }
    }
    if same { return first, nearest }
    sum: [3]f64
    alpha := 0.0
    for dy in 0 ..< factor {
        for dx in 0 ..< factor {
            c := u32le(device.color, (((y * factor + dy) * width) + x * factor + dx) * 4)
            a := f64(c >> 24) / 255
            alpha += a
            for channel in 0 ..< 3 {
                value := clamp(f64((c >> u32(channel * 8)) & 255) / max(a, 0.00001), 0, 255)
                lower := int(value)
                upper := min(255, lower + 1)
                linear :=
                    SOFTWARE_SRGB_DECODE[lower] +
                    (SOFTWARE_SRGB_DECODE[upper] - SOFTWARE_SRGB_DECODE[lower]) *
                        (value - f64(lower))
                sum[channel] += linear * a
            }
        }
    }
    coverage := alpha / f64(factor * factor)
    c := u32(clamp(pixel_round(coverage * 255), 0, 255)) << 24
    for channel in 0 ..< 3 { c |= software_encode(sum[channel] / max(alpha, 0.00001), coverage) << u32(channel * 8) }
    return c, nearest
}

software_triangle :: proc(t: ^Transaction, input: [3]Clip_Vertex, camera: []u8) -> bool {
    any, all := u32(0), u32(63)
    for vertex in input {
        code := u32(0)
        for plane in 0 ..< 6 {
            if clip_distance(vertex.p, plane) < 0 { code |= 1 << u32(plane) }
        }
        any |= code
        all &= code
    }
    if all != 0 { return true }
    if any == 0 { return raster_triangle(t, input, camera, account = false) }
    poly: [CLIP_CAPACITY]Clip_Vertex
    for vertex, i in input { poly[i] = vertex }
    count := 3
    for plane in 0 ..< 6 {
        if count == 0 { break }
        next: [CLIP_CAPACITY]Clip_Vertex
        n := 0
        previous := poly[count - 1]
        pd := clip_distance(previous.p, plane)
        for current in poly[:count] {
            cd := clip_distance(current.p, plane)
            if (pd >= 0) != (cd >= 0) {
                if n == len(next) { return false }
                next[n] = clip_lerp(previous, current, pd / (pd - cd))
                n += 1
            }
            if cd >= 0 {
                if n == len(next) { return false }
                next[n] = current
                n += 1
            }
            previous, pd = current, cd
        }
        poly, count = next, n
    }
    for i := 1; i + 1 < count; i += 1 {
        if !raster_triangle(
            t,
            {poly[0], poly[i], poly[i + 1]},
            camera,
            account = false,
        ) { return false }
    }
    return true
}

software_raster :: proc(job: Raster_Job) -> bool {
    if len(job.draws) != 0 { return false }
    factor := max(1, min(software_quality, 1920 / job.width, 1080 / job.height))
    border := 1 if len(job.border) != 0 else 0
    rw, rh := job.width + border * 2, job.height + border * 2
    width, height := rw * factor, rh * factor
    if width * height > 1932 * 1092 { return false }
    if software_device == nil {
        pointer, error := mem.alloc(size_of(Software_Device), align_of(Software_Device))
        if error != nil { return false }
        mem.zero(pointer, size_of(Software_Device))
        software_device = cast(^Software_Device)pointer
    }
    device := software_device
    if device.width != width || device.height != height {
        size := width * height * 4
        color, color_error := mem.alloc(size, 4)
        if color_error != nil { return false }
        depth, depth_error := mem.alloc(size, 4)
        if depth_error != nil { mem.free(color); return false }
        delete(device.color)
        delete(device.depth)
        device.color = (cast([^]u8)color)[:size]
        device.depth = (cast([^]u8)depth)[:size]
        device.width, device.height = width, height
    }
    for y in 0 ..< height {
        sy := y / factor - border
        for x in 0 ..< width {
            sx := x / factor - border
            color, depth := u32(0), transmute(u32)f32(1)
            if sx >= 0 && sx < job.width && sy >= 0 && sy < job.height {
                at := (sy * job.width + sx) * 4
                color, depth = u32le(job.color, at), u32le(job.depth, at)
            }
            at := (y * width + x) * 4
            put32(device.color, at, color)
            put32(device.depth, at, depth)
        }
    }
    device.registry.screen = Slot {
        kind   = .Target,
        format = w.format_rgba8,
        width  = u32(width),
        height = u32(height),
        data   = device.color,
    }
    device.registry.slots[0] = Slot {
        kind       = .Depth,
        generation = 1,
        width      = u32(width),
        height     = u32(height),
        data       = device.depth,
    }
    t := Transaction {
        registry = &device.registry,
        slots    = &device.registry.slots,
        screen   = &device.registry.screen,
    }
    t.render.depth = w.handleGenerationStride | 1
    t.render.clip = {
        i32((int(job.clip[0]) + border) * factor),
        i32((int(job.clip[1]) + border) * factor),
        job.clip[2] * i32(factor),
        job.clip[3] * i32(factor),
    }
    if border != 0 { t.render.clip = {0, 0, i32(width), i32(height)} }
    camera: [w.cameraBytes]u8
    put32(camera[:], w.cameraFogColorOffset, job.fog_color)
    putf(camera[:], w.cameraFogStartOffset, f64(job.fog_start))
    putf(camera[:], w.cameraFogEndOffset, f64(job.fog_end))
    for at := 0; at < len(job.vertices); at += 3 * RASTER_VERTEX_BYTES {
        input: [3]Clip_Vertex
        for &vertex, i in input {
            for &value, axis in vertex.p { value = f32le(job.vertices, at + i * RASTER_VERTEX_BYTES + axis * 4) }
            vertex.p[0] *= f64(job.width) / f64(rw)
            vertex.p[1] *= f64(job.height) / f64(rh)
            for &value, channel in vertex.color { value = f32le(job.vertices, at + i * RASTER_VERTEX_BYTES + 16 + channel * 4) }
        }
        if !software_triangle(&t, input, camera[:]) { return false }
    }
    for y in 0 ..< rh {
        for x in 0 ..< rw {
            c, nearest := software_resolve(device, x, y, width, factor)
            if border != 0 { put32(job.border, (y * rw + x) * 4, c) }
            sx, sy := x - border, y - border
            if sx >= 0 && sx < job.width && sy >= 0 && sy < job.height {
                at := (sy * job.width + sx) * 4
                put32(job.color, at, c)
                putf(job.depth, at, nearest)
            }
        }
    }
    return true
}

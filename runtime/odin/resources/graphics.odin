package resources

import abi "../abi"
import audio "../audio"
import core "../core"
import w "../resource_protocol"
import "core:math"
import "core:mem"

Transaction :: struct {
    registry:                                             ^Registry,
    slots:                                                ^[w.maxSlots]Slot,
    screen:                                               ^Slot,
    retained, budget, work, width, height, present_count: int,
    output:                                               []u32,
    render:                                               Render_State,
    copy_bytes:                                           u64,
    peak:                                                 int,
    audio:                                                audio.Transaction,
    audio_created:                                        bool,
}
Render_State :: struct {
    active:   bool,
    target:   u32,
    pipeline: [8]u32,
    clip:     [4]i32,
    affine:   [6]i32,
}
lookup :: proc(t: ^Transaction, id: u32, kind: Kind = .Empty) -> ^Slot {
    slot: ^Slot
    if id == 0 {

        slot = t.screen
    } else {
        index, gen := id & w.handleIndexMask, id >> w.handleIndexBits
        if index == 0 || index > w.maxSlots || gen == 0 {

            return nil
        }
        slot = &t.slots[index - 1]
        if slot.generation != gen {

            return nil
        }
    }
    if slot.kind == .Empty || (kind != .Empty && slot.kind != kind) {

        return nil
    }
    return slot
}
image :: proc(t: ^Transaction, id: u32) -> ^Slot {
    slot := lookup(t, id)
    if slot == nil || (slot.kind != .Texture && slot.kind != .Target) {

        return nil
    }
    return slot
}
unused :: proc(t: ^Transaction, id: u32) -> ^Slot {
    index, gen := id & w.handleIndexMask, id >> w.handleIndexBits
    if index == 0 || index > w.maxSlots || gen == 0 {

        return nil
    }
    slot := &t.slots[index - 1]
    if slot.kind != .Empty || slot.generation != gen {

        return nil
    }
    return slot
}
referenced :: proc(t: ^Transaction, id: u32) -> bool {
    for slot in t.slots^ {
        if slot.kind == .Empty {

            continue
        }
        if slot.link == id && id != 0 {

            return true
        }
        if slot.kind == .Row_Table {

            for at := 0; at < len(slot.data); at += 12 {

                if u32le(slot.data, at) == id {

                    return true
                }
            }
        }
    }
    return false
}
allocate :: proc(t: ^Transaction, size: int) -> ([]u8, bool) {
    if size < 0 || size > t.budget - t.retained {

        return nil, fail(t.registry, "graphics allocation exceeds resource budget")
    }
    ptr, err := mem.alloc(size, 4)
    if err != nil {

        return nil, fail(t.registry, "graphics allocation failed")
    }
    data := (cast([^]u8)ptr)[:size]
    mem.zero(ptr, size)
    t.retained += size
    return data, true
}
owned :: proc(t: ^Transaction, id: u32) -> ^Slot {
    slot := image(t, id)
    if slot == nil {

        fail(t.registry, "invalid image handle")
        return nil
    }
    original := &t.registry.screen if id == 0 else &t.registry.slots[(id & w.handleIndexMask) - 1]
    size := int(slot.width) * int(slot.height) * (4 if slot.format == w.format_rgba8 else 1)
    if raw_data(slot.data) == raw_data(original.data) || len(slot.data) != size {
        data, ok := allocate(t, size)
        if !ok {

            return nil
        }
        if len(slot.data) == size {

            copy(data, slot.data)
            t.copy_bytes += u64(size)
        }
        if raw_data(slot.data) != raw_data(original.data) {

            t.retained -= len(slot.data)
            delete(slot.data)
        }
        slot.data = data
    }
    return slot
}
premultiplied :: proc(value: u32) -> bool {
    return(
        (value & 255) <= value >> 24 &&
        ((value >> 8) & 255) <= value >> 24 &&
        ((value >> 16) & 255) <= value >> 24 \
    )
}
valid_palette :: proc(data: []u8) -> bool {
    if len(data) % 4 != 0 {

        return false
    }
    for at := 0; at < len(data); at += 4 {

        if !premultiplied(u32le(data, at)) {

            return false
        }
    }
    return true
}
default_pipeline :: proc(format: u32) -> [8]u32 {
    return {
        format,
        0,
        0,
        15 if format == w.format_rgba8 else 255,
        0,
        0x00ffff00,
        0,
        0,
    }
}
pipeline :: proc(t: ^Transaction, id, format, stencil: u32) -> ([8]u32, bool) {
    value := default_pipeline(format)
    if id >= w.defaultRgbaPipelineId {
        if (id == w.defaultRgbaPipelineId && format != w.format_rgba8) ||
           (id == w.defaultIndexPipelineId && format != w.format_index8) ||
           id == w.invalidPipelineId {

            return value, fail(t.registry, "default pipeline format mismatch")
        }
    } else if id != 0 {
        slot := lookup(t, id, .Pipeline)
        if slot == nil {

            return value, fail(t.registry, "invalid pipeline handle")
        }
        for &field, i in value {

            field = u32le(slot.data, i * 4)
        }
    }
    if value[0] != format {

        return value, fail(t.registry, "pipeline and target formats differ")
    }
    if stencil == 0 && (value[4] != 0 || value[6] != 0) {

        return value, fail(t.registry, "pipeline requires a stencil attachment")
    }
    return value, true
}
graphics_control :: proc(t: ^Transaction, op, id: u32, descriptor: [8]u32, data: []u8) -> bool {
    args := descriptor
    r := t.registry
    if op == w.op_destroy_resource {
        slot := lookup(t, id)
        if id == 0 || slot == nil || slot.kind == .Texture || slot.kind == .Sample {

            return fail(r, "invalid graphics destroy handle")
        }
        if referenced(t, id) {

            return fail(r, "resource is still referenced")
        }
        original := &r.slots[(id & w.handleIndexMask) - 1]
        if raw_data(slot.data) != raw_data(original.data) {

            t.retained -= len(slot.data)
            delete(slot.data)
        }
        slot^ = Slot {
            generation = slot.generation + 1,
        }
        return len(data) == 0 || fail(r, "unexpected destroy payload")
    }
    if op == w.op_write_buffer {
        slot := lookup(t, id)
        if slot == nil ||
           (slot.kind != .Palette && slot.kind != .Color_Table && slot.kind != .Row_Table) {

            return fail(r, "invalid mutable graphics buffer")
        }
        for field in args[1:] {

            if field != 0 {

                return fail(r, "nonzero buffer padding")
            }
        }
        if !within(args[0], u32(len(data)), len(slot.data)) {

            return fail(r, "graphics write outside buffer")
        }
        if slot.kind == .Palette && (args[0] % 4 != 0 || !valid_palette(data)) {

            return fail(r, "invalid palette write")
        }
        if slot.kind == .Row_Table {
            if args[0] % 12 != 0 || len(data) % 12 != 0 {

                return fail(r, "unaligned row table write")
            }
            for at := 0; at < len(data); at += 12 {
                if lookup(t, u32le(data, at), .Palette) == nil {

                    return fail(r, "invalid row palette")
                }
                if abs(i64(i32(u32le(data, at + 4)))) > abi.COORDINATE_MAX ||
                   abs(i64(i32(u32le(data, at + 8)))) > abi.COORDINATE_MAX {

                    return fail(r, "row offset outside supported range")
                }
            }
        }
        if len(data) == 0 {

            return true
        }
        original := &r.slots[(id & w.handleIndexMask) - 1]
        if raw_data(slot.data) == raw_data(original.data) {
            buffer, ok := allocate(t, len(slot.data))
            if !ok {

                return false
            }
            copy(buffer, slot.data)
            t.copy_bytes += u64(len(buffer))
            slot.data = buffer
        }
        copy(slot.data[int(args[0]):], data)
        t.copy_bytes += u64(len(data))
        return true
    }
    slot := unused(t, id)
    if slot == nil {

        return fail(r, "graphics creation requires an unused current-generation handle")
    }
    kind: Kind
    size: int
    format, width, height, link: u32
    switch op {
    case w.op_create_target:
        format, width, height, link = args[0], args[1], args[2], args[3]
        if (format != w.format_rgba8 &&
               format != w.format_index8 &&
               format != w.format_stencil8) ||
           width == 0 ||
           width > w.maxImageAxis ||
           height == 0 ||
           height > w.maxImageAxis {

            return fail(r, "invalid target descriptor")
        }
        count := 0; for entry in t.slots^ {

            if entry.kind == .Target {

                count += 1
            }
        }
        if count >= w.maxTargets {

            return fail(r, "offscreen target limit exceeded")
        }
        if link != 0 {
            stencil := lookup(t, link, .Target)
            if format == w.format_stencil8 ||
               stencil == nil ||
               stencil.format != w.format_stencil8 ||
               stencil.width != width ||
               stencil.height != height {

                return fail(r, "invalid stencil attachment")
            }
        }
        for field in args[4:] {

            if field != 0 {

                return fail(r, "nonzero target padding")
            }
        }
        kind = .Target; size = int(width) * int(height) * (4 if format == w.format_rgba8 else 1)
    case w.op_create_palette:
        kind = .Palette; size = 1024
    case w.op_create_color_table:
        kind = .Color_Table; size = w.colorTableBytes
    case w.op_create_row_table:
        if args[0] == 0 || args[0] > 360 {

            return fail(r, "invalid row table length")
        }
        kind = .Row_Table; width = args[0]; size = int(width) * 12
        for field in args[1:] {

            if field != 0 {

                return fail(r, "nonzero row descriptor padding")
            }
        }
    case w.op_create_pipeline:
        if (args[0] != w.format_rgba8 && args[0] != w.format_index8) ||
           args[1] > 3 ||
           args[4] > 2 ||
           args[5] > 0xffffff ||
           args[6] > 3 ||
           args[7] > 256 {

            return fail(r, "invalid pipeline descriptor")
        }
        if (args[0] == w.format_rgba8 && (args[1] == 3 || args[3] > 15)) ||
           (args[0] == w.format_index8 && (args[1] == 1 || args[1] == 2 || args[3] > 255)) {

            return fail(r, "incompatible pipeline blend or mask")
        }
        if args[1] == 3 {

            if lookup(t, args[2], .Color_Table) == nil {

                return fail(r, "invalid composition table")
            }
        } else if args[2] != 0 {

            return fail(r, "unexpected composition table")
        }
        kind = .Pipeline
        format = args[0]
        link = args[2]
        size = 32
    case:
        return fail(r, "unknown resource opcode")
    }
    if op == w.op_create_palette || op == w.op_create_color_table {
        for field in args {

            if field != 0 {

                return fail(r, "nonzero table descriptor padding")
            }
        }
    }
    if len(data) != 0 && !((kind == .Palette || kind == .Color_Table) && len(data) == size) {

        return fail(r, "unexpected graphics creation payload")
    }
    if kind == .Palette && !valid_palette(data) {

        return fail(r, "invalid premultiplied palette")
    }
    bytes, ok := allocate(t, size)
    if !ok {

        return false
    }
    if kind == .Pipeline {

        for field, i in args {

            put32(bytes, i * 4, field)
        }
    } else {

        copy(bytes, data)
        t.copy_bytes += u64(len(data))
    }
    slot^ = Slot {
        generation = slot.generation,
        kind       = kind,
        format     = format,
        width      = width,
        height     = height,
        link       = link,
        data       = bytes,
    }
    return true
}

graphics_command :: proc(
    t: ^Transaction,
    op, id: u32,
    descriptor: [8]u32,
    data: []u8,
    phase: u32,
) -> bool {
    args := descriptor
    r := t.registry
    if op <= w.op_destroy_resource {
        if phase == 2 {

            return fail(r, "resource creation/edit in draw packet")
        }
        return graphics_control(t, op, id, args, data)
    }
    if phase != 2 {

        return fail(r, "graphics command outside draw packet")
    }
    if op != w.op_draw && op != w.op_text && len(data) != 0 {

        return fail(r, "unexpected graphics payload")
    }
    if (op == w.op_end_pass ||
           op == w.op_clip ||
           op == w.op_transform ||
           op == w.op_rect ||
           op == w.op_clear ||
           op == w.op_text ||
           op == w.op_sprite) &&
       id != 0 {

        return fail(r, "unexpected graphics primary handle")
    }
    state := &t.render
    switch op {
    case w.op_begin_pass:
        if state.active {

            return fail(r, "nested graphics pass")
        }
        target := lookup(t, id, .Target)
        if target == nil || target.format == w.format_stencil8 {

            return fail(r, "invalid color target")
        }
        pipe, ok := pipeline(t, args[0], target.format, target.link); if !ok {

            return false
        }
        if args[1] > 1 ||
           args[3] > 1 ||
           args[4] > 255 ||
           args[5] != 0 ||
           args[6] != 0 ||
           args[7] != 0 {

            return fail(r, "invalid pass options")
        }
        target = owned(t, id); if target == nil {

            return false
        }
        if target.link != 0 {

            if owned(t, target.link) == nil {

                return false
            }
        }
        state^ = Render_State {
            active   = true,
            target   = id,
            pipeline = pipe,
            clip     = {0, 0, i32(target.width), i32(target.height)},
            affine   = {w.graphicsFixedOne, 0, 0, w.graphicsFixedOne, 0, 0},
        }
        if args[1] != 0 {

            if !clear_target(t, args[2], args[3] != 0, args[4]) {

                return false
            }
        } else if args[3] != 0 {

            if !clear_stencil(t, args[4]) {

                return false
            }
        }
    case w.op_end_pass:
        if !state.active {

            return fail(r, "end without a graphics pass")
        }; state.active = false
    case w.op_clip:
        if !state.active {

            return fail(r, "clip outside pass")
        }
        for i in 0 ..< 4 {

            state.clip[i] = i32(args[i])
            if abs(i64(state.clip[i])) > abi.COORDINATE_MAX || (i >= 2 && state.clip[i] < 0) {

                return fail(r, "invalid clip rectangle")
            }
        }
        for field in args[4:] {

            if field != 0 {

                return fail(r, "nonzero clip padding")
            }
        }
    case w.op_transform:
        if !state.active {

            return fail(r, "transform outside pass")
        }
        for i in 0 ..< 6 {

            state.affine[i] = i32(args[i])
            if abs(i64(state.affine[i])) >
               i64(
                   w.maxAffineCoefficient * w.graphicsFixedOne if i < 4 else abi.COORDINATE_MAX * w.graphicsFixedOne,
               ) {

                return fail(r, "transform outside supported range")
            }
        }
        if i64(state.affine[0]) * i64(state.affine[3]) -
                   i64(state.affine[1]) * i64(state.affine[2]) ==
               0 ||
           args[6] != 0 ||
           args[7] != 0 {

            return fail(r, "singular transform or nonzero padding")
        }
    case w.op_bind:
        if !state.active {

            return fail(r, "bind outside pass")
        }
        target := image(t, state.target)
        pipe, ok := pipeline(t, id, target.format, target.link); if !ok {

            return false
        }; state.pipeline = pipe
    case w.op_rect:
        if !state.active {

            return fail(r, "rectangle outside pass")
        }
        if args[5] != 0 || args[6] != 0 || args[7] != 0 {

            return fail(r, "nonzero rectangle padding")
        }
        return raster(
            t,
            {i32(args[0]), i32(args[1]), i32(args[2]), i32(args[3])},
            nil,
            {},
            0,
            args[4],
            0,
            false,
        )
    case w.op_clear:
        if !state.active || args[1] > 1 || args[2] > 255 {

            return fail(r, "invalid pass clear")
        }
        for field in args[3:] {

            if field != 0 {

                return fail(r, "nonzero clear padding")
            }
        }
        return clear_target(t, args[0], args[1] != 0, args[2])
    case w.op_draw:
        if !state.active || id == state.target || len(data) != 32 {

            return fail(r, "draw feedback, missing pass or invalid quad descriptor")
        }
        source := image(t, id)
        if source == nil || source.format == w.format_stencil8 {

            return fail(r, "invalid sampled image")
        }
        if id == 0 {

            source = owned(t, 0)
            if source == nil {

                return false
            }
        }
        quad: [8]u32
        for &field, i in quad {

            field = u32le(data, i * 4)
        }
        if quad[6] > 7 || quad[7] != 0 {

            return fail(r, "invalid image sampling flags")
        }
        for field in args[4:] {

            if field != 0 {

                return fail(r, "nonzero image padding")
            }
        }
        palette_id := quad[4]
        if source.format == w.format_index8 && image(t, state.target).format == w.format_rgba8 {
            if lookup(t, palette_id, .Palette) == nil {

                return fail(r, "indexed conversion requires a palette")
            }
        } else if palette_id != 0 {

            return fail(r, "unexpected draw palette")
        }
        if source.format == w.format_rgba8 && image(t, state.target).format != w.format_rgba8 {

            return fail(r, "RGBA-to-index conversion is unsupported")
        }
        return raster(
            t,
            {i32(quad[0]), i32(quad[1]), i32(quad[2]), i32(quad[3])},
            source,
            {i32(args[0]), i32(args[1]), i32(args[2]), i32(args[3])},
            palette_id,
            quad[5],
            quad[6],
            false,
        )
    case w.op_copy:
        if state.active || id == args[0] {

            return fail(r, "copy requires distinct images outside passes")
        }
        source := image(t, id)
        dest := image(t, args[0])
        if source == nil ||
           dest == nil ||
           source.format != dest.format ||
           !rect_fits(source, args[1], args[2], args[3], args[4]) ||
           !rect_fits(dest, args[5], args[6], args[3], args[4]) ||
           args[7] != 0 {

            return fail(r, "invalid image copy")
        }
        if id == 0 {

            source = owned(t, 0)
            if source == nil {

                return false
            }
        }
        dest = owned(t, args[0])
        if dest == nil {

            return false
        }
        bpp := 4 if source.format == w.format_rgba8 else 1
        if !charge(t, int(args[3]) * int(args[4])) {

            return false
        }
        for y in 0 ..< int(args[4]) {

            copy(
                dest.data[((int(args[6]) + y) * int(dest.width) + int(args[5])) *
                bpp:][:int(args[3]) *
                bpp],
                source.data[((int(args[2]) + y) * int(source.width) + int(args[1])) *
                bpp:][:int(args[3]) *
                bpp],
            )
        }
        t.copy_bytes += u64(args[3]) * u64(args[4]) * u64(bpp)
    case w.op_present:
        if state.active || t.present_count != 0 {

            return fail(r, "presentation requires closed passes and occurs once")
        }
        return present(t, id, args)
    case w.op_readback:
        if state.active {

            return fail(r, "readback inside pass")
        }
        source := image(t, args[0]); slot := unused(t, id)
        if source == nil ||
           source.format == w.format_stencil8 ||
           slot == nil ||
           !rect_fits(source, args[1], args[2], args[3], args[4]) {

            return fail(r, "invalid readback request")
        }
        for field in args[5:] {

            if field != 0 {

                return fail(r, "nonzero readback padding")
            }
        }
        count := 0; for entry in t.slots^ {

            if entry.kind == .Readback {

                count += 1
            }
        }
        size := int(args[3]) * int(args[4]) * (4 if source.format == w.format_rgba8 else 1)
        if count >= w.maxReadbacks || size > w.maxReadbackBytes {

            return fail(r, "readback capacity exceeded")
        }
        if args[0] == 0 {

            source = owned(t, 0)
            if source == nil {

                return false
            }
        }
        bytes, ok := allocate(t, size); if !ok {

            return false
        }
        bpp := 4 if source.format == w.format_rgba8 else 1
        for y in 0 ..< int(args[4]) {

            copy(
                bytes[y * int(args[3]) * bpp:][:int(args[3]) * bpp],
                source.data[((int(args[2]) + y) * int(source.width) + int(args[1])) *
                bpp:][:int(args[3]) *
                bpp],
            )
        }
        slot^ = Slot {
            generation = slot.generation,
            kind       = .Readback,
            format     = source.format,
            width      = args[3],
            height     = args[4],
            data       = bytes,
        }
        t.copy_bytes += u64(size)
    case w.op_text, w.op_sprite:
        if !state.active || core.sprite_count == 0 {

            return fail(r, "sprite/text requires a pass and loaded assets")
        }
        return convenience(t, op, args, data)
    case:
        return fail(r, "unknown graphics opcode")
    }
    if len(data) != 0 {

        return fail(r, "unexpected graphics payload")
    }
    return true
}
rect_fits :: proc(slot: ^Slot, x, y, width, height: u32) -> bool {
    return(
        width > 0 &&
        height > 0 &&
        u64(x) + u64(width) <= u64(slot.width) &&
        u64(y) + u64(height) <= u64(slot.height) \
    )
}
charge :: proc(t: ^Transaction, pixels: int) -> bool {
    if pixels < 0 || pixels > w.maxPixelWork - t.work {

        return fail(t.registry, "graphics pixel-work budget exceeded")
    }
    t.work += pixels
    return true
}
clear_stencil :: proc(t: ^Transaction, value: u32) -> bool {
    target := image(t, t.render.target)
    stencil := lookup(t, target.link, .Target)
    if target.link == 0 || stencil == nil {

        return fail(t.registry, "clear requires a stencil attachment")
    }
    if !charge(t, len(stencil.data)) {

        return false
    }
    for &byte in stencil.data {

        byte = u8(value)
    }
    return true
}
clear_target :: proc(t: ^Transaction, value: u32, stencil: bool, stencil_value: u32) -> bool {
    target := image(t, t.render.target)
    if (target.format == w.format_rgba8 && !premultiplied(value)) ||
       (target.format == w.format_index8 && value > 255) {

        return fail(t.registry, "invalid target clear color")
    }
    if !charge(t, int(target.width) * int(target.height)) {

        return false
    }
    if target.format == w.format_rgba8 {

        for at := 0; at < len(target.data); at += 4 {

            put32(target.data, at, value)
        }
    } else {

        for &byte in target.data {

            byte = u8(value)
        }
    }
    if stencil {

        return clear_stencil(t, stencil_value)
    }
    return true
}
over :: proc(src, dst: u32) -> u32 {
    inv := 255 - (src >> 24)
    result: u32
    for shift in 0 ..< 4 {

        s := u32(shift * 8)
        result |= min(u32(255), ((src >> s) & 255) + (((dst >> s) & 255) * inv + 127) / 255) << s
    }
    return result
}
tint_color :: proc(src, tint: u32) -> u32 {
    result: u32
    for shift in 0 ..< 4 {

        s := u32(shift * 8)
        result |= ((((src >> s) & 255) * ((tint >> s) & 255) + 127) / 255) << s
    }
    return result
}
fragment :: proc(t: ^Transaction, target: ^Slot, x, y: int, value: u32) -> bool {
    p := t.render.pipeline
    if target.format == w.format_index8 && p[7] != 0 && value == p[7] - 1 {

        return true
    }
    at := y * int(target.width) + x
    if target.link != 0 {
        stencil := lookup(t, target.link, .Target)
        old := u32(stencil.data[at])
        ref, read_mask, write_mask := p[5] & 255, (p[5] >> 8) & 255, (p[5] >> 16) & 255
        equal := (old & read_mask) == (ref & read_mask)
        passes := p[4] == 0 || (p[4] == 1 && equal) || (p[4] == 2 && !equal)
        replace := (p[6] & 1) != 0 if passes else (p[6] & 2) != 0
        if replace {

            stencil.data[at] = u8((old &~ write_mask) | (ref & write_mask))
        }
        if !passes {

            return true
        }
    }
    if target.format == w.format_index8 {
        old := u32(target.data[at])
        out := value
        if p[1] == 3 {

            out = u32(lookup(t, p[2], .Color_Table).data[int(value) * 256 + int(old)])
        }
        target.data[at] = u8((old &~ p[3]) | (out & p[3]))
        return true
    }
    old := u32le(target.data, at * 4)
    out := value
    if p[1] == 1 {

        out = over(value, old)
    } else if p[1] == 2 {
        out = 0
        for shift in 0 ..< 4 {

            s := u32(shift * 8)
            out |= min(u32(255), ((value >> s) & 255) + ((old >> s) & 255)) << s
        }
    }
    mask: u32
    for channel in 0 ..< 4 {

        if p[3] & (1 << u32(channel)) != 0 {

            mask |= 255 << u32(channel * 8)
        }
    }
    out = (old &~ mask) | (out & mask)
    if !premultiplied(out) {

        return fail(t.registry, "channel mask produced non-premultiplied RGBA")
    }
    put32(target.data, at * 4, out)
    return true
}

// Quantized inputs, pixel centers, inverse affine mapping and half-open local
// rectangles define coverage. Integer products fit exactly in binary64 here.
raster :: proc(
    t: ^Transaction,
    rect: [4]i32,
    source: ^Slot,
    src: [4]i32,
    palette_id, color, flags: u32,
    skip_zero: bool,
) -> bool {
    target := image(t, t.render.target)
    for value in rect {

        if abs(i64(value)) > abi.COORDINATE_MAX * w.graphicsFixedOne {

            return fail(t.registry, "draw geometry outside supported range")
        }
    }
    if rect[2] < 0 || rect[3] < 0 {

        return fail(t.registry, "negative draw size")
    }
    if target.format == w.format_rgba8 && !premultiplied(color) {

        return fail(t.registry, "invalid premultiplied draw color")
    }
    if target.format == w.format_index8 && source != nil && color != abi.COLOR_OPAQUE_WHITE {

        return fail(t.registry, "indexed draw cannot tint RGBA")
    }
    if source == nil && target.format == w.format_index8 && color > 255 {

        return fail(t.registry, "invalid indexed rectangle color")
    }
    if source != nil {
        if src[2] <= 0 || src[3] <= 0 {

            return fail(t.registry, "invalid source rectangle")
        }
        for value in src {

            if abs(i64(value)) > abi.COORDINATE_MAX {

                return fail(t.registry, "source rectangle outside supported range")
            }
        }
    }
    if rect[2] == 0 || rect[3] == 0 {

        return true
    }
    m := t.render.affine
    a, b, c, d, tx, ty :=
        f64(m[0]) /
        w.graphicsFixedOne,
        f64(m[1]) /
        w.graphicsFixedOne,
        f64(m[2]) /
        w.graphicsFixedOne,
        f64(m[3]) /
        w.graphicsFixedOne,
        f64(m[4]) /
        w.graphicsFixedOne,
        f64(m[5]) /
        w.graphicsFixedOne
    det := a * d - b * c
    rx, ry, rw, rh :=
        f64(rect[0]) /
        w.graphicsFixedOne,
        f64(rect[1]) /
        w.graphicsFixedOne,
        f64(rect[2]) /
        w.graphicsFixedOne,
        f64(rect[3]) /
        w.graphicsFixedOne
    min_x, min_y, max_x, max_y := f64(1e30), f64(1e30), -f64(1e30), -f64(1e30)
    for corner in 0 ..< 4 {
        x := rx + (rw if corner & 1 != 0 else 0)
        y := ry + (rh if corner & 2 != 0 else 0)
        xx, yy := a * x + c * y + tx, b * x + d * y + ty
        min_x = min(min_x, xx)
        min_y = min(min_y, yy)
        max_x = max(max_x, xx)
        max_y = max(max_y, yy)
    }
    clip := t.render.clip
    x0 := max(0, int(clip[0]), int(math.floor(min_x)))
    y0 := max(0, int(clip[1]), int(math.floor(min_y)))
    x1 := min(int(target.width), int(clip[0] + clip[2]), int(math.ceil(max_x)))
    y1 := min(int(target.height), int(clip[1] + clip[3]), int(math.ceil(max_y)))
    if x0 >= x1 || y0 >= y1 {

        return true
    }
    if !charge(t, (x1 - x0) * (y1 - y0)) {

        return false
    }
    for y in y0 ..< y1 {
        for x in x0 ..< x1 {
            dx, dy := f64(x) + 0.5 - tx, f64(y) + 0.5 - ty
            lx, ly := (d * dx - c * dy) / det, (a * dy - b * dx) / det
            if lx < rx || ly < ry || lx >= rx + rw || ly >= ry + rh {

                continue
            }
            value := color
            if source != nil {
                u, v :=
                    clamp(int(math.floor((lx - rx) * f64(src[2]) / rw)), 0, int(src[2]) - 1),
                    clamp(int(math.floor((ly - ry) * f64(src[3]) / rh)), 0, int(src[3]) - 1)
                if flags & 1 != 0 {

                    u = int(src[2]) - 1 - u
                }
                if flags & 2 != 0 {

                    v = int(src[3]) - 1 - v
                }
                sx, sy := int(src[0]) + u, int(src[1]) + v
                if flags & 4 != 0 {

                    sx = wrap(sx, int(source.width))
                    sy = wrap(sy, int(source.height))
                } else {

                    sx = clamp(sx, 0, int(source.width) - 1)
                    sy = clamp(sy, 0, int(source.height) - 1)
                }
                at := sy * int(source.width) + sx
                if source.format == w.format_index8 {
                    value = u32(source.data[at])
                    if t.render.pipeline[7] != 0 && value == t.render.pipeline[7] - 1 {

                        continue
                    }
                    if target.format == w.format_rgba8 {

                        value = u32le(lookup(t, palette_id, .Palette).data, int(value) * 4)
                    }
                } else {

                    value = u32le(source.data, at * 4)
                }
                if skip_zero && value == 0 {

                    continue
                }
                if target.format == w.format_rgba8 {

                    value = tint_color(value, color)
                }
            }
            if !fragment(t, target, x, y, value) {

                return false
            }
        }
    }
    return true
}
wrap :: proc(value, size: int) -> int {
    result := value % size
    return result + size if result < 0 else result
}
present :: proc(t: ^Transaction, id: u32, descriptor: [8]u32) -> bool {
    args := descriptor
    source := image(t, id)
    if source == nil ||
       source.format == w.format_stencil8 ||
       int(source.width) != t.width ||
       int(source.height) != t.height ||
       args[2] > 1 ||
       args[3] >> 24 != 255 {

        return fail(t.registry, "invalid presentation descriptor")
    }
    for field in args[4:] {

        if field != 0 {

            return fail(t.registry, "nonzero presentation padding")
        }
    }
    if id == 0 {

        source = owned(t, 0)
        if source == nil {

            return false
        }
    }
    rows := lookup(t, args[1], .Row_Table)
    if source.format == w.format_rgba8 {
        if args[0] != 0 || args[1] != 0 {

            return fail(t.registry, "RGBA presentation does not use palette/rows")
        }
    } else {
        if args[1] != 0 && (rows == nil || int(rows.width) != t.height) {

            return fail(t.registry, "row table does not match output height")
        }
        if args[1] == 0 && lookup(t, args[0], .Palette) == nil {

            return fail(t.registry, "indexed presentation requires a palette")
        }
    }
    bytes, ok := allocate(t, t.width * t.height * 4)
    if !ok {

        return false
    }
    t.output = (cast([^]u32)raw_data(bytes))[:t.width * t.height]
    if !charge(t, t.width * t.height) {

        return false
    }
    for y in 0 ..< t.height {
        for x in 0 ..< t.width {
            value: u32
            if source.format == w.format_rgba8 {

                value = u32le(source.data, (y * t.width + x) * 4)
            } else {
                palette_id := args[0]
                sx, sy := x, y
                if args[1] != 0 {

                    palette_id = u32le(rows.data, y * 12)
                    sx += int(i32(u32le(rows.data, y * 12 + 4)))
                    sy += int(i32(u32le(rows.data, y * 12 + 8)))
                }
                palette := lookup(t, palette_id, .Palette)
                if palette == nil {

                    return fail(t.registry, "invalid row palette handle")
                }
                if args[2] != 0 {

                    sx = wrap(sx, t.width)
                    sy = wrap(sy, t.height)
                } else {

                    sx = clamp(sx, 0, t.width - 1)
                    sy = clamp(sy, 0, t.height - 1)
                }
                value = u32le(palette.data, int(source.data[sy * t.width + sx]) * 4)
            }
            t.output[y * t.width + x] = over(value, args[3])
        }
    }
    t.present_count += 1
    return true
}
convenience :: proc(t: ^Transaction, op: u32, descriptor: [8]u32, data: []u8) -> bool {
    args := descriptor
    if op == w.op_text {
        if len(data) > 1024 {

            return fail(t.registry, "text exceeds supported length")
        }
        for value in args[3:] {

            if value != 0 {

                return fail(t.registry, "nonzero text padding")
            }
        }
        x, y := i32(args[0]), i32(args[1])
        start := x
        for char in data {
            if char >= 128 {

                return fail(t.registry, "text must be ASCII")
            }
            if char == 10 {

                x = start
                y += 9 * w.graphicsFixedOne
                continue
            }
            for row in 0 ..< 7 {
                for col in 0 ..< 5 {
                    if core.font[char][row] & (1 << u8(4 - col)) != 0 {
                        if !raster(t, {
                                x + i32(col) * w.graphicsFixedOne,
                                y + i32(row) * w.graphicsFixedOne,
                                w.graphicsFixedOne,
                                w.graphicsFixedOne,
                            }, nil, {}, 0, args[2], 0, false) {

                            return false
                        }
                    }
                }
            }
            x += 6 * w.graphicsFixedOne
        }
        return true
    }
    if args[0] >= u32(core.sprite_count) ||
       len(data) != 0 ||
       image(t, t.render.target).format != w.format_rgba8 ||
       args[6] != 0 ||
       args[7] != 0 {

        return fail(t.registry, "invalid legacy atlas sprite")
    }
    bytes := (cast([^]u8)&core.atlas[args[0]])[:256 * 4]
    source := Slot {
        kind   = .Texture,
        format = w.format_rgba8,
        width  = 16,
        height = 16,
        data   = bytes,
    }
    return raster(
        t,
        {i32(args[1]), i32(args[2]), i32(args[3]), i32(args[4])},
        &source,
        {0, 0, 16, 16},
        0,
        args[5],
        0,
        true,
    )
}
apply_output :: proc(r: ^Registry) {
    if r.has_output {

        copy(core.pixels[:r.output_width * r.output_height], r.output)
        r.stats.copy_bytes += u64(len(r.output) * 4)
    }
}

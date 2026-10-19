package gfx

import w "../../../runtime/odin/resource_protocol"
import r "../../../runtime/odin/resources"
import data "../data"
import t "../resource"
import "core:math"
Texture :: distinct t.Handle
Target :: distinct t.Handle
Palette :: distinct t.Handle
Color_Table :: distinct t.Handle
Row_Table :: distinct t.Handle
Pipeline :: distinct t.Handle
Readback :: distinct t.Handle
Pass :: struct {
    session, epoch, serial: u32,
}
Target_Desc :: struct {
    format:        data.Pixel_Format,
    width, height: u32,
    stencil:       Target,
}
Blend :: enum u32 {
    Replace,
    Over,
    Add,
    Table,
}
Compare :: enum u32 {
    Always,
    Equal,
    Not_Equal,
}
Optional_U32 :: union {
    u32,
}
optional :: proc(value: Optional_U32, fallback: u32) -> u32 {
    result, ok := value.(u32)
    return result if ok else fallback
}
Stencil :: struct {
    compare:                    Compare,
    reference:                  u32,
    read_mask, write_mask:      Optional_U32,
    replace_pass, replace_fail: bool,
}
Pipeline_Desc :: struct {
    format:            data.Pixel_Format,
    blend:             Blend,
    color_table:       Color_Table,
    write_mask:        Optional_U32,
    stencil:           Stencil,
    transparent_index: Optional_U32,
}
Pass_Options :: struct {
    pipeline:      Pipeline,
    clear:         bool,
    color:         u32,
    clear_stencil: bool,
    stencil:       u32,
}
Draw_Options :: struct {
    palette:                      Palette,
    tint:                         Optional_U32,
    flip_x, flip_y, repeat_image: bool,
}
Present_Options :: struct {
    palette:      Palette,
    rows:         Row_Table,
    repeat_image: bool,
    background:   Optional_U32,
}
Source_Rect :: struct {
    x, y, width, height: i32,
}
Quad :: struct {
    x, y, width, height: f64,
}
Row :: struct {
    palette: Palette,
    x, y:    i32,
}
Texture_Desc :: struct {
    format:        data.Pixel_Format,
    width, height: u32,
}
Rect :: struct {
    x, y, width, height: u32,
}
Upload :: struct {
    offset_bytes, stride_bytes: u32,
}
texture :: proc(desc: Texture_Desc) -> Texture {
    if !t.valid(
        (desc.format == .Index8 || desc.format == .RGBA8) &&
        desc.width > 0 &&
        desc.width <= w.maxImageAxis &&
        desc.height > 0 &&
        desc.height <= w.maxImageAxis,
        "invalid texture descriptor",
    ) {

        return {}
    }
    handle := t.reserve(1, u32(desc.format))
    args := [8]u32{u32(desc.format), desc.width, desc.height, 0, 0, 0, 0, 0}
    t.emit(w.op_create_texture, handle, args[:])
    return Texture(handle)
}
upload :: proc(target: $Image, rect: Rect, pixels: data.Pixel_Buffer, opts := Upload{}) {
    #assert(Image == Texture || Image == Target)
    handle := t.Handle(target)
    if !t.check(handle, 0) {

        return
    }
    if !t.valid(
        u32(pixels.format) == t.slots[(handle.id & w.handleIndexMask) - 1].format &&
        pixels.width > 0 &&
        pixels.height > 0 &&
        len(pixels.bytes) > 0,
        "texture and pixel buffer formats differ or buffer is empty",
    ) {

        return
    }
    stride := opts.stride_bytes
    if stride == 0 {

        stride = u32(pixels.width) * (4 if pixels.format == .RGBA8 else 1)
    }
    args := [8]u32{rect.x, rect.y, rect.width, rect.height, opts.offset_bytes, stride, 0, 0}
    t.emit(w.op_write_texture, handle, args[:], pixels.bytes)
}

q :: proc(value: f64, limit: f64 = 4096) -> u32 {
    if !t.valid(
        !math.is_nan(value) && !math.is_inf(value) && abs(value) <= limit,
        "graphics coordinate outside supported range",
    ) {

        return 0
    }
    return u32(i32(math.floor(value * 65536 + 0.5)))
}
rgba :: proc(red, green, blue, alpha: u32) -> u32 {
    if !t.valid(
        red <= 255 && green <= 255 && blue <= 255 && alpha <= 255,
        "invalid color channel",
    ) {

        return 0
    }
    return(
        ((red * alpha + 127) / 255) |
        ((green * alpha + 127) / 255) << 8 |
        ((blue * alpha + 127) / 255) << 16 |
        alpha << 24 \
    )
}
screen :: proc() -> Target {

    return Target(t.Handle{t.session, 0})
}
default_pipeline :: proc(format: data.Pixel_Format) -> Pipeline {
    if !t.valid(format == .RGBA8 || format == .Index8, "invalid default pipeline format") {

        return {}
    }
    return Pipeline(t.Handle{t.session, 0xfffffffd if format == .RGBA8 else 0xfffffffe})
}
pipeline_id :: proc(value: Pipeline) -> u32 {
    handle := t.Handle(value)
    if handle.id == 0 {

        return 0
    }
    if handle.id >= 0xfffffffd {

        if !t.valid(handle.session == t.session, "stale default pipeline") {

            return 0
        }
    } else if !t.check(handle, 7) {

        return 0
    }
    return handle.id
}
target :: proc(desc: Target_Desc) -> Target {
    if desc.stencil.id == 0 && desc.stencil.session != 0 {

        t.fail("reserved screen cannot be a stencil attachment")
        return {}
    }
    if desc.stencil.id != 0 && !t.check(t.Handle(desc.stencil), 3) {

        return {}
    }
    if desc.stencil.id != 0 &&
       !t.valid(
               t.slots[(desc.stencil.id & w.handleIndexMask) - 1].format == w.format_stencil8,
               "attachment requires a stencil target",
           ) {

        return {}
    }
    handle := t.reserve(3, u32(desc.format))
    args := [8]u32{u32(desc.format), desc.width, desc.height, desc.stencil.id, 0, 0, 0, 0}
    t.emit(w.op_create_target, handle, args[:])
    return Target(handle)
}
palette :: proc(colors: []u32 = nil) -> Palette {
    handle := t.reserve(4, 0)
    args: [8]u32
    bytes := (cast([^]u8)raw_data(colors))[:len(colors) * 4]
    t.emit(w.op_create_palette, handle, args[:], bytes)
    return Palette(handle)
}
color_table :: proc(bytes: []u8 = nil) -> Color_Table {
    handle := t.reserve(5, 0)
    args: [8]u32
    t.emit(w.op_create_color_table, handle, args[:], bytes)
    return Color_Table(handle)
}
row_table :: proc(rows: u32) -> Row_Table {
    handle := t.reserve(6, 0)
    args := [8]u32{rows, 0, 0, 0, 0, 0, 0, 0}
    t.emit(w.op_create_row_table, handle, args[:])
    return Row_Table(handle)
}
pipeline :: proc(desc: Pipeline_Desc) -> Pipeline {
    if desc.color_table.id != 0 && !t.check(t.Handle(desc.color_table), 5) {

        return {}
    }
    stencil := desc.stencil
    transparent, enabled := desc.transparent_index.(u32)
    if !t.valid(
        stencil.reference <= 255 &&
        optional(stencil.read_mask, 255) <= 255 &&
        optional(stencil.write_mask, 255) <= 255 &&
        (!enabled || transparent <= 255),
        "invalid pipeline masks/index",
    ) {

        return {}
    }
    mask := optional(desc.write_mask, 15 if desc.format == .RGBA8 else 255)
    handle := t.reserve(7, u32(desc.format))
    args := [8]u32 {
        u32(desc.format),
        u32(desc.blend),
        desc.color_table.id,
        mask,
        u32(stencil.compare),
        stencil.reference | optional(stencil.read_mask, 255) << 8 | optional(stencil.write_mask, 255) << 16,
        u32(stencil.replace_pass) | u32(stencil.replace_fail) << 1,
        transparent + 1 if enabled else 0,
    }
    t.emit(w.op_create_pipeline, handle, args[:])
    return Pipeline(handle)
}
write :: proc(target: $Buffer, offset_bytes: u32, bytes: []u8) {
    #assert(Buffer == Palette || Buffer == Color_Table || Buffer == Row_Table)
    handle := t.Handle(target)
    if !t.check(handle, 0) {

        return
    }
    args := [8]u32 {
        offset_bytes,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
    }
    t.emit(w.op_write_buffer, handle, args[:], bytes)
}
write_rows :: proc(target: Row_Table, first: u32, rows: []Row) {
    if !t.valid(
        first <= 360 && len(rows) <= 360 && u64(first) + u64(len(rows)) <= 360,
        "row write exceeds staging limit",
    ) {

        return
    }
    bytes: [360 * 12]u8
    for row, i in rows {
        if !t.check(t.Handle(row.palette), 4) {

            return
        }
        r.put32(bytes[:], i * 12, row.palette.id)
        r.put32(bytes[:], i * 12 + 4, u32(row.x))
        r.put32(bytes[:], i * 12 + 8, u32(row.y))
    }
    write(target, first * 12, bytes[:len(rows) * 12])
}
draw_ready :: proc() -> bool {
    return t.ready() && t.valid(t.phase == 2, "graphics commands require draw")
}
image_valid :: proc(value: $Image) -> bool {
    #assert(Image == Texture || Image == Target)
    handle := t.Handle(value)
    if handle.id == 0 {

        return t.check(handle, 3)
    }
    return(
        t.check(handle, 0) &&
        t.valid(
            t.slots[(handle.id & w.handleIndexMask) - 1].kind == 1 ||
            t.slots[(handle.id & w.handleIndexMask) - 1].kind == 3,
            "invalid image kind",
        ) \
    )
}
current_pass :: proc() -> Pass {

    return {t.session, t.draw_epoch, t.active_pass}
}
check_pass :: proc(pass: Pass) -> bool {
    return(
        draw_ready() &&
        t.valid(
            pass.session == t.session &&
            pass.epoch == t.draw_epoch &&
            pass.serial != 0 &&
            pass.serial == t.active_pass,
            "stale or ended graphics pass",
        ) \
    )
}
begin_pass :: proc(target: Target, opts := Pass_Options{}) -> Pass {
    if !draw_ready() ||
       !t.valid(t.active_pass == 0, "nested graphics pass") ||
       !t.check(t.Handle(target), 3) {

        return {}
    }
    if !t.valid(t.pass_serial != max(u32), "pass serial exhausted") {

        return {}
    }
    t.pass_serial += 1
    t.active_pass = t.pass_serial
    args := [8]u32 {
        pipeline_id(opts.pipeline),
        u32(opts.clear),
        opts.color,
        u32(opts.clear_stencil),
        opts.stencil,
        0,
        0,
        0,
    }
    t.emit(w.op_begin_pass, t.Handle(target), args[:])
    return current_pass()
}
end_pass :: proc(pass: Pass) {
    if check_pass(pass) {
        t.emit(w.op_end_pass, {})
        t.active_pass = 0
    }
}
bind :: proc(pass: Pass, value: Pipeline) {
    if check_pass(pass) {
        t.emit(w.op_bind, {t.session, pipeline_id(value)})
    }
}
clip :: proc(pass: Pass, x, y, width, height: i32) {
    if !check_pass(pass) {

        return
    }
    args := [8]u32{u32(x), u32(y), u32(width), u32(height), 0, 0, 0, 0}
    t.emit(w.op_clip, {}, args[:])
}
transform :: proc(pass: Pass, affine: [6]f64) {
    if !check_pass(pass) {

        return
    }
    args: [8]u32
    for value, i in affine {

        args[i] = q(value, 16 if i < 4 else 4096)
    }
    t.emit(w.op_transform, {}, args[:])
}
rect :: proc(pass: Pass, x, y, width, height: f64, color: u32) {
    if !check_pass(pass) {

        return
    }
    args := [8]u32{q(x), q(y), q(width), q(height), color, 0, 0, 0}
    t.emit(w.op_rect, {}, args[:])
}
clear :: proc(pass: Pass, color: u32, stencil: bool = false, value: u32 = 0) {
    if !check_pass(pass) {

        return
    }
    args := [8]u32{color, u32(stencil), value, 0, 0, 0, 0, 0}
    t.emit(w.op_clear, {}, args[:])
}
draw :: proc(pass: Pass, source: $Image, src: Source_Rect, dst: Quad, opts := Draw_Options{}) {
    #assert(Image == Texture || Image == Target)
    handle := t.Handle(source)
    if !check_pass(pass) || !(t.check(handle, 3) if handle.id == 0 else t.check(handle, 0)) {

        return
    }
    if opts.palette.id != 0 && !t.check(t.Handle(opts.palette), 4) {

        return
    }
    args := [8]u32{u32(src.x), u32(src.y), u32(src.width), u32(src.height), 0, 0, 0, 0}
    quad := [8]u32 {
        q(dst.x),
        q(dst.y),
        q(dst.width),
        q(dst.height),
        opts.palette.id,
        optional(opts.tint, 0xffffffff),
        u32(opts.flip_x) | u32(opts.flip_y) << 1 | u32(opts.repeat_image) << 2,
        0,
    }
    t.emit(w.op_draw, handle, args[:], (cast([^]u8)&quad)[:32])
}
copy :: proc(source: $Source, destination: $Destination, src: Rect, x, y: u32) {
    #assert(Source == Texture || Source == Target)
    #assert(Destination == Texture || Destination == Target)
    if !draw_ready() || !image_valid(source) || !image_valid(destination) {

        return
    }
    args := [8]u32{destination.id, src.x, src.y, src.width, src.height, x, y, 0}
    t.emit(w.op_copy, t.Handle(source), args[:])
}
present :: proc(source: $Image, opts := Present_Options{}) {
    #assert(Image == Texture || Image == Target)
    if !draw_ready() || !image_valid(source) {

        return
    }
    if opts.palette.id != 0 && !t.check(t.Handle(opts.palette), 4) {

        return
    }
    if opts.rows.id != 0 && !t.check(t.Handle(opts.rows), 6) {

        return
    }
    args := [8]u32 {
        opts.palette.id,
        opts.rows.id,
        u32(opts.repeat_image),
        optional(opts.background, 0xff000000),
        0,
        0,
        0,
        0,
    }
    t.emit(w.op_present, t.Handle(source), args[:])
}
readback :: proc(source: $Image, rect: Rect) -> Readback {
    #assert(Image == Texture || Image == Target)
    if !draw_ready() ||
       !image_valid(source) ||
       !t.valid(t.active_pass == 0, "readback inside pass") {

        return {}
    }
    handle := t.reserve(8, 0)
    args := [8]u32{source.id, rect.x, rect.y, rect.width, rect.height, 0, 0, 0}
    t.emit(w.op_readback, handle, args[:])
    return Readback(handle)
}
poll :: proc(ticket: Readback) -> (data.Pixel_Buffer, bool) {
    if !t.check(t.Handle(ticket), 8) || !t.valid(t.phase != 2, "poll requires init/update") {

        return {}, false
    }
    result := t.results[(ticket.id & w.handleIndexMask) - 1]
    if len(result.bytes) == 0 {

        return {}, false
    }
    t.results[(ticket.id & w.handleIndexMask) - 1] = {}
    t.destroy(t.Handle(ticket), 8)
    return {
            data.Pixel_Format(result.format),
            int(result.width),
            int(result.height),
            result.bytes,
            result.allocator,
        }, true
}
destroy :: proc(target: $Resource) {
    #assert(
        Resource == Texture ||
        Resource == Target ||
        Resource == Palette ||
        Resource == Color_Table ||
        Resource == Row_Table ||
        Resource == Pipeline ||
        Resource == Readback,
    )
    handle := t.Handle(target)
    if !t.check(handle, 0) {

        return
    }
    t.destroy(handle, t.slots[(handle.id & w.handleIndexMask) - 1].kind)
}
text :: proc(pass: Pass, value: string, x, y: f64, color: u32) {
    if !check_pass(pass) {

        return
    }
    args := [8]u32{q(x), q(y), color, 0, 0, 0, 0, 0}
    t.emit(w.op_text, {}, args[:], transmute([]u8)value)
}
sprite :: proc(pass: Pass, id: int, x, y, width, height: f64, tint: u32 = 0xffffffff) {
    if !check_pass(pass) {

        return
    }
    args := [8]u32{u32(id), q(x), q(y), q(width), q(height), tint, 0, 0}
    t.emit(w.op_sprite, {}, args[:])
}

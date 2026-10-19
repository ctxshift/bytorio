--!strict
local host = require("./native")
local schema = require("./resource_schema")
export type Texture = { _resourceKind: "texture" }
export type Target = { _resourceKind: "target" }
export type Palette = { _resourceKind: "palette" }
export type ColorTable = { _resourceKind: "color_table" }
export type RowTable = { _resourceKind: "row_table" }
export type Pipeline = { _resourceKind: "pipeline" }
export type Readback = { _resourceKind: "readback" }
export type Image = Texture | Target
export type Pass = { read session: number, read epoch: number, read serial: number }
export type Sample = { _resourceKind: "sample" }
export type PixelBuffer = {
    read format: "index8" | "rgba8" | "stencil8",
    read width: number,
    read height: number,
    read bytes: buffer,
}
export type PCMBuffer = { read frames: number, read channels: number, read samples: buffer }
export type TextureDesc = { format: "index8" | "rgba8", width: number, height: number }
export type SampleDesc = { frames: number, channels: number, rate: number }
export type Rect = { x: number, y: number, width: number, height: number }
export type FrameRange = { first: number, frames: number }
export type Upload = { offset_bytes: number?, stride_bytes: number? }
type Handle = Texture | Sample | Target | Palette | ColorTable | RowTable | Pipeline | Readback
type Record = { session: number, id: number, kind: string, format: number, channels: number }
local records: { [Handle]: Record } = setmetatable({}, { __mode = "k" }) :: any
local slots: { [number]: { generation: number, live: boolean } } = {}
local session, active = 0, false
local api = {}
local phase = "load"
local epoch, serial = 0, 0
local activePass: Pass? = nil
local results: { [number]: PixelBuffer } = {}
local function integer(value: number, lo: number, hi: number): number
    assert(value == math.floor(value) and value >= lo and value <= hi, "invalid resource integer")
    return value
end
local function ready()
    assert(active and session ~= 0, "resource operations require a configured init/update callback")
end
local function reserve(kind: string, format: number, channels: number): Handle
    ready()
    assert(phase ~= "draw" or kind == "readback", "resource creation requires init/update")
    for i = 1, schema.maxSlots do
        local slot = slots[i]
        if not slot then
            slot = { generation = 1, live = false }
            slots[i] = slot
        end
        if not slot.live and slot.generation <= 65535 then
            slot.live = true
            local handle = table.freeze({ _resourceKind = kind }) :: any
            records[handle] = {
                session = session,
                id = slot.generation * 65536 + i,
                kind = kind,
                format = format,
                channels = channels,
            }
            return handle
        end
    end
    error("resource slot capacity exceeded")
end
local function check(handle: Handle, kind: string): Record
    ready()
    local record = records[handle]
    assert(
        record
            and record.session == session
            and (
                record.kind == kind
                or kind == "any"
                or (kind == "image" and (record.kind == "texture" or record.kind == "target"))
            ),
        "wrong resource kind or stale session"
    )
    if record.id == 0 and record.kind == "target" then
        return record
    end
    if record.id >= 4294967293 and record.kind == "pipeline" then
        return record
    end
    local slot = slots[record.id % 65536]
    assert(
        slot and slot.live and slot.generation == math.floor(record.id / 65536),
        "stale resource generation"
    )
    return record
end
local function emit(op: number, id: number, values: { number }?, bytes: buffer?)
    assert(
        (op <= 13 and phase ~= "draw") or (op >= 16 and phase == "draw"),
        "resource command in wrong callback phase"
    )
    local args = buffer.create(if values then 32 else 0)
    if values then
        for i, value in values do
            buffer.writeu32(args, (i - 1) * 4, value % 4294967296)
        end
    end
    host.resource_emit(op, id, args, bytes or buffer.create(0))
end
local function destroy(handle: Handle, kind: string)
    local record = check(handle, kind)
    emit(
        if kind == "texture"
            then schema.op_destroy_texture
            elseif kind == "sample" then schema.op_destroy_sample
            else schema.op_destroy_resource,
        record.id
    )
    results[record.id] = nil
    local slot = slots[record.id % 65536]
    slot.live = false
    slot.generation += 1
end
local data = {}
function data.pixels(
    format: "index8" | "rgba8" | "stencil8",
    width: number,
    height: number
): PixelBuffer
    assert(
        format == "index8" or format == "rgba8" or format == "stencil8",
        "unsupported pixel format"
    )
    integer(width, 1, schema.maxImageAxis)
    integer(height, 1, schema.maxImageAxis)
    return table.freeze({
        format = format :: "rgba8" | "index8" | "stencil8",
        width = width,
        height = height,
        bytes = buffer.create(width * height * (if format == "rgba8" then 4 else 1)),
    })
end
function data.pcm(frames: number, channels: number): PCMBuffer
    integer(frames, 1, schema.maxPayload / 4)
    integer(channels, 1, 2)
    assert(frames * channels * 4 <= schema.maxPayload, "PCM staging capacity exceeded")
    return table.freeze({
        frames = frames,
        channels = channels,
        samples = buffer.create(frames * channels * 4),
    })
end
function data.get_pixel(pixels: PixelBuffer, x: number, y: number): number
    integer(x, 0, pixels.width - 1)
    integer(y, 0, pixels.height - 1)
    local at = y * pixels.width + x
    return if pixels.format == "rgba8"
        then buffer.readu32(pixels.bytes, at * 4)
        else buffer.readu8(pixels.bytes, at)
end
function data.set_pixel(pixels: PixelBuffer, x: number, y: number, color: number)
    integer(x, 0, pixels.width - 1)
    integer(y, 0, pixels.height - 1)
    local at = y * pixels.width + x
    if pixels.format == "rgba8" then
        integer(color, 0, 4294967295)
        local alpha = math.floor(color / 16777216)
        assert(
            color % 256 <= alpha
                and math.floor(color / 256) % 256 <= alpha
                and math.floor(color / 65536) % 256 <= alpha,
            "invalid premultiplied pixel"
        )
        buffer.writeu32(pixels.bytes, at * 4, color)
    else
        buffer.writeu8(pixels.bytes, at, integer(color, 0, 255))
    end
end
function data.fill_pixels(pixels: PixelBuffer, color: number)
    if pixels.format ~= "rgba8" then
        buffer.fill(pixels.bytes, 0, integer(color, 0, 255))
    else
        for y = 0, pixels.height - 1 do
            for x = 0, pixels.width - 1 do
                data.set_pixel(pixels, x, y, color)
            end
        end
    end
end
function data.copy_pixels(
    destination: PixelBuffer,
    dx: number,
    dy: number,
    source: PixelBuffer,
    sx: number,
    sy: number,
    width: number,
    height: number
)
    assert(destination.format == source.format, "pixel copy formats differ")
    integer(width, 0, 1024)
    integer(height, 0, 1024)
    integer(dx, 0, destination.width - width)
    integer(dy, 0, destination.height - height)
    integer(sx, 0, source.width - width)
    integer(sy, 0, source.height - height)
    local bpp = if source.format == "rgba8" then 4 else 1
    local backwards = destination.bytes == source.bytes and dy > sy
    for i = 0, height - 1 do
        local row = if backwards then height - 1 - i else i
        buffer.copy(
            destination.bytes,
            ((dy + row) * destination.width + dx) * bpp,
            source.bytes,
            ((sy + row) * source.width + sx) * bpp,
            width * bpp
        )
    end
end
local gfx = {}
function gfx.texture(desc: TextureDesc): Texture
    assert(desc.format == "index8" or desc.format == "rgba8", "unsupported pixel format")
    integer(desc.width, 1, schema.maxImageAxis)
    integer(desc.height, 1, schema.maxImageAxis)
    local format = if desc.format == "rgba8" then schema.format_rgba8 else schema.format_index8
    local handle = reserve("texture", format, 0)
    emit(schema.op_create_texture, records[handle].id, { format, desc.width, desc.height })
    return handle :: Texture
end
function gfx.upload(target: Image, rect: Rect, pixels: PixelBuffer, opts: Upload?)
    local record = check(target, "image")
    local format = if pixels.format == "rgba8"
        then schema.format_rgba8
        elseif pixels.format == "stencil8" then schema.format_stencil8
        else schema.format_index8
    assert(record.format == format, "texture and pixel buffer formats differ")
    local bpp = if format == schema.format_rgba8 then 4 else 1
    integer(rect.x, 0, schema.maxImageAxis)
    integer(rect.y, 0, schema.maxImageAxis)
    integer(rect.width, 1, schema.maxImageAxis)
    integer(rect.height, 1, schema.maxImageAxis)
    local offset = integer(if opts then opts.offset_bytes or 0 else 0, 0, schema.maxPayload)
    local stride = integer(
        if opts then opts.stride_bytes or pixels.width * bpp else pixels.width * bpp,
        0,
        schema.maxPayload
    )
    if stride == 0 then
        stride = pixels.width * bpp
    end
    emit(
        schema.op_write_texture,
        record.id,
        { rect.x, rect.y, rect.width, rect.height, offset, stride },
        pixels.bytes
    )
end
function gfx.destroy(
    target: Texture | Target | Palette | ColorTable | RowTable | Pipeline | Readback
)
    local record = check(target, "any")
    destroy(target, record.kind)
end
local audio = {}
function audio.write(target: Sample, range: FrameRange, pcm: PCMBuffer)
    local record = check(target, "sample")
    integer(range.first, 0, schema.maxResourceBytes / 4)
    integer(range.frames, 1, schema.maxPayload / 4)
    assert(
        pcm.channels == record.channels
            and pcm.frames == range.frames
            and buffer.len(pcm.samples) == pcm.frames * pcm.channels * 4,
        "PCM descriptor does not match buffer"
    )
    emit(schema.op_write_sample, record.id, { range.first, range.frames }, pcm.samples)
end
function audio.sample(desc: SampleDesc, pcm: PCMBuffer?): Sample
    integer(desc.frames, 1, schema.maxResourceBytes / 4)
    integer(desc.channels, 1, 2)
    integer(desc.rate, 8000, 96000)
    assert(desc.frames * desc.channels * 4 <= schema.maxResourceBytes, "sample capacity exceeded")
    local handle = reserve("sample", schema.format_f32, desc.channels)
    emit(
        schema.op_create_sample,
        records[handle].id,
        { schema.format_f32, desc.frames, desc.channels, desc.rate }
    )
    if pcm then
        audio.write(handle :: Sample, { first = 0, frames = pcm.frames }, pcm)
    end
    return handle :: Sample
end
function audio.destroy(target: Sample)
    destroy(target, "sample")
end
export type Stencil = {
    compare: ("always" | "equal" | "not_equal")?,
    reference: number?,
    read_mask: number?,
    write_mask: number?,
    replace_pass: boolean?,
    replace_fail: boolean?,
}
export type PipelineDesc = {
    format: "index8" | "rgba8",
    blend: ("replace" | "over" | "add" | "table")?,
    color_table: ColorTable?,
    write_mask: number?,
    stencil: Stencil?,
    transparent_index: number?,
}
export type PassOptions = {
    pipeline: Pipeline?,
    clear: boolean?,
    color: number?,
    clear_stencil: boolean?,
    stencil: number?,
}
export type DrawOptions = {
    palette: Palette?,
    tint: number?,
    flip_x: boolean?,
    flip_y: boolean?,
    repeat_image: boolean?,
}
export type PresentOptions = {
    palette: Palette?,
    rows: RowTable?,
    repeat_image: boolean?,
    background: number?,
}
export type Row = { palette: Palette, x: number, y: number }
local function formatId(format: string): number
    assert(
        format == "rgba8" or format == "index8" or format == "stencil8",
        "unsupported pixel format"
    )
    return if format == "rgba8"
        then schema.format_rgba8
        elseif format == "index8" then schema.format_index8
        else schema.format_stencil8
end
local function id(handle: Handle?, kind: string): number
    return if handle then check(handle, kind).id else 0
end
local function fixed(value: number, limit: number?): number
    local bound = limit or 4096
    assert(
        value == value and value >= -bound and value <= bound,
        "graphics coordinate outside supported range"
    )
    return math.floor(value * 65536 + 0.5) % 4294967296
end
local function drawReady()
    ready()
    assert(phase == "draw", "graphics commands require draw")
end
local function checkPass(pass: Pass)
    drawReady()
    assert(
        activePass
            and pass.session == session
            and pass.epoch == epoch
            and pass.serial == activePass.serial,
        "stale or ended graphics pass"
    )
end
local function reserved(kind: string, value: number, format: number): Handle
    ready()
    local handle = table.freeze({ _resourceKind = kind }) :: any
    records[handle] = { session = session, id = value, kind = kind, format = format, channels = 0 }
    return handle
end
function gfx.rgba(r: number, g: number, b: number, a: number): number
    integer(r, 0, 255)
    integer(g, 0, 255)
    integer(b, 0, 255)
    integer(a, 0, 255)
    return math.floor((r * a + 127) / 255)
        + math.floor((g * a + 127) / 255) * 256
        + math.floor((b * a + 127) / 255) * 65536
        + a * 16777216
end
function gfx.screen(): Target
    return reserved("target", 0, schema.format_rgba8) :: Target
end
function gfx.default_pipeline(format: "rgba8" | "index8"): Pipeline
    assert(format == "rgba8" or format == "index8", "invalid default pipeline format")
    return reserved(
        "pipeline",
        if format == "rgba8" then 4294967293 else 4294967294,
        formatId(format)
    ) :: Pipeline
end
function gfx.target(desc: {
    format: "rgba8" | "index8" | "stencil8",
    width: number,
    height: number,
    stencil: Target?,
}): Target
    local format = formatId(desc.format)
    integer(desc.width, 1, 1024)
    integer(desc.height, 1, 1024)
    if desc.stencil then
        local attachment = check(desc.stencil, "target")
        assert(
            attachment.id ~= 0 and attachment.format == schema.format_stencil8,
            "attachment requires a stencil target"
        )
    end
    local handle = reserve("target", format, 0)
    emit(
        schema.op_create_target,
        records[handle].id,
        { format, desc.width, desc.height, id(desc.stencil, "target") }
    )
    return handle :: Target
end
function gfx.palette(colors: buffer?): Palette
    local handle = reserve("palette", 0, 0)
    emit(schema.op_create_palette, records[handle].id, {}, colors)
    return handle :: Palette
end
function gfx.color_table(bytes: buffer?): ColorTable
    local handle = reserve("color_table", 0, 0)
    emit(schema.op_create_color_table, records[handle].id, {}, bytes)
    return handle :: ColorTable
end
function gfx.row_table(rows: number): RowTable
    integer(rows, 1, 360)
    local handle = reserve("row_table", 0, 0)
    emit(schema.op_create_row_table, records[handle].id, { rows })
    return handle :: RowTable
end
function gfx.pipeline(desc: PipelineDesc): Pipeline
    local format = formatId(desc.format)
    local blends = { replace = 0, over = 1, add = 2, table = 3 }
    local compares = { always = 0, equal = 1, not_equal = 2 }
    local stencil: Stencil = desc.stencil or {}
    local readMask = integer(stencil.read_mask or 255, 0, 255)
    local writeMask = integer(stencil.write_mask or 255, 0, 255)
    local reference = integer(stencil.reference or 0, 0, 255)
    local transparent = if desc.transparent_index ~= nil
        then integer(desc.transparent_index, 0, 255) + 1
        else 0
    local blend = blends[desc.blend or "replace"]
    local compare = compares[stencil.compare or "always"]
    assert(blend ~= nil and compare ~= nil, "invalid pipeline blend or compare")
    local handle = reserve("pipeline", format, 0)
    emit(schema.op_create_pipeline, records[handle].id, {
        format,
        blend,
        id(desc.color_table, "color_table"),
        integer(desc.write_mask or (if format == schema.format_rgba8 then 15 else 255), 0, 255),
        compare,
        reference + readMask * 256 + writeMask * 65536,
        (if stencil.replace_pass then 1 else 0) + (if stencil.replace_fail then 2 else 0),
        transparent,
    })
    return handle :: Pipeline
end
function gfx.write(target: Palette | ColorTable | RowTable, offset_bytes: number, bytes: buffer)
    local record = check(target, "any")
    integer(offset_bytes, 0, 65536)
    emit(schema.op_write_buffer, record.id, { offset_bytes }, bytes)
end
function gfx.write_rows(target: RowTable, first: number, rows: { Row })
    integer(first, 0, 360)
    assert(#rows <= 360, "row write exceeds staging limit")
    local bytes = buffer.create(#rows * 12)
    for i, row in rows do
        buffer.writeu32(bytes, (i - 1) * 12, id(row.palette, "palette"))
        buffer.writei32(bytes, (i - 1) * 12 + 4, integer(row.x, -4096, 4096))
        buffer.writei32(bytes, (i - 1) * 12 + 8, integer(row.y, -4096, 4096))
    end
    gfx.write(target, first * 12, bytes)
end
function gfx.current_pass(): Pass
    assert(activePass, "no active graphics pass")
    return activePass
end
function gfx.begin_pass(target: Target, opts: PassOptions?): Pass
    drawReady()
    assert(activePass == nil, "nested graphics pass")
    local options: PassOptions = opts or {}
    serial += 1
    local pass = table.freeze({ session = session, epoch = epoch, serial = serial })
    activePass = pass
    emit(schema.op_begin_pass, id(target, "target"), {
        id(options.pipeline, "pipeline"),
        if options.clear then 1 else 0,
        options.color or 0,
        if options.clear_stencil then 1 else 0,
        options.stencil or 0,
    })
    return pass
end
function gfx.end_pass(pass: Pass)
    checkPass(pass)
    emit(schema.op_end_pass, 0)
    activePass = nil
end
function gfx.bind(pass: Pass, value: Pipeline)
    checkPass(pass)
    emit(schema.op_bind, id(value, "pipeline"))
end
function gfx.clip(pass: Pass, x: number, y: number, width: number, height: number)
    checkPass(pass)
    emit(schema.op_clip, 0, {
        integer(x, -4096, 4096),
        integer(y, -4096, 4096),
        integer(width, 0, 4096),
        integer(height, 0, 4096),
    })
end
function gfx.transform(pass: Pass, affine: { number })
    checkPass(pass)
    assert(#affine == 6, "affine transform needs six values")
    local values = {}
    for i, value in affine do
        values[i] = fixed(value, if i <= 4 then 16 else 4096)
    end
    emit(schema.op_transform, 0, values)
end
function gfx.rect(pass: Pass, x: number, y: number, width: number, height: number, color: number)
    checkPass(pass)
    emit(schema.op_rect, 0, { fixed(x), fixed(y), fixed(width), fixed(height), color })
end
function gfx.clear(pass: Pass, color: number, stencil: boolean?, value: number?)
    checkPass(pass)
    emit(schema.op_clear, 0, { color, if stencil then 1 else 0, value or 0 })
end
function gfx.draw(pass: Pass, source: Image, src: Rect, dst: Rect, opts: DrawOptions?)
    checkPass(pass)
    local options: DrawOptions = opts or {}
    local quad = buffer.create(32)
    local fields = {
        fixed(dst.x),
        fixed(dst.y),
        fixed(dst.width),
        fixed(dst.height),
        id(options.palette, "palette"),
        options.tint or 4294967295,
        (if options.flip_x then 1 else 0)
            + (if options.flip_y then 2 else 0)
            + (if options.repeat_image then 4 else 0),
    }
    for i, value in fields do
        buffer.writeu32(quad, (i - 1) * 4, value)
    end
    emit(schema.op_draw, id(source, "image"), {
        integer(src.x, -4096, 4096),
        integer(src.y, -4096, 4096),
        integer(src.width, 1, 4096),
        integer(src.height, 1, 4096),
    }, quad)
end
function gfx.copy(source: Image, destination: Image, src: Rect, x: number, y: number)
    drawReady()
    emit(
        schema.op_copy,
        id(source, "image"),
        { id(destination, "image"), src.x, src.y, src.width, src.height, x, y }
    )
end
function gfx.present(source: Image, opts: PresentOptions?)
    drawReady()
    local options: PresentOptions = opts or {}
    emit(schema.op_present, id(source, "image"), {
        id(options.palette, "palette"),
        id(options.rows, "row_table"),
        if options.repeat_image then 1 else 0,
        options.background or 4278190080,
    })
end
function gfx.readback(source: Image, rect: Rect): Readback
    drawReady()
    assert(activePass == nil, "readback inside pass")
    local handle = reserve("readback", 0, 0)
    emit(
        schema.op_readback,
        records[handle].id,
        { id(source, "image"), rect.x, rect.y, rect.width, rect.height }
    )
    return handle :: Readback
end
function gfx.poll(ticket: Readback): PixelBuffer?
    local record = check(ticket, "readback")
    assert(phase ~= "draw", "poll requires init/update")
    local result = results[record.id]
    if result then
        results[record.id] = nil
        destroy(ticket, "readback")
    end
    return result
end
function gfx.text(pass: Pass, value: string, x: number, y: number, color: number)
    checkPass(pass)
    local bytes = buffer.fromstring(value)
    emit(schema.op_text, 0, { fixed(x), fixed(y), color }, bytes)
end
function gfx.sprite(
    pass: Pass,
    sprite: number,
    x: number,
    y: number,
    width: number,
    height: number,
    tint: number?
)
    checkPass(pass)
    emit(
        schema.op_sprite,
        0,
        { sprite, fixed(x), fixed(y), fixed(width), fixed(height), tint or 4294967295 }
    )
end
function api._begin(tick: number)
    if tick == 0 then
        session = host.resource_session()
        slots = {}
        results = {}
    else
        for _, result in host.resource_results() do
            results[result.id] = table.freeze({
                format = (
                        if result.format == schema.format_rgba8 then "rgba8" else "index8"
                    ) :: "rgba8" | "index8",
                width = result.width,
                height = result.height,
                bytes = result.bytes,
            })
        end
    end
    phase = "control"
    active = true
end
function api._begin_draw()
    phase = "draw"
    active = true
    epoch += 1
    activePass = nil
end
function api._in_pass(): boolean
    return activePass ~= nil
end
function api._end()
    assert(activePass == nil, "graphics pass was not ended")
    active = false
end
api.gfx = table.freeze(gfx)
api.audio = table.freeze(audio)
api.data = table.freeze(data)
return table.freeze(api)

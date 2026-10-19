--!strict
local host = require("./native")
local schema = require("./resource_schema")
export type Texture = {_resourceKind: "texture"}
export type Sample = {_resourceKind: "sample"}
export type PixelBuffer = {read format: "index8" | "rgba8", read width: number, read height: number, read bytes: buffer}
export type PCMBuffer = {read frames: number, read channels: number, read samples: buffer}
export type TextureDesc = {format: "index8" | "rgba8", width: number, height: number}
export type SampleDesc = {frames: number, channels: number, rate: number}
export type Rect = {x: number, y: number, width: number, height: number}
export type FrameRange = {first: number, frames: number}
export type Upload = {offset_bytes: number?, stride_bytes: number?}
type Handle = Texture | Sample
type Record = {session: number, id: number, kind: string, format: number, channels: number}
local records: {[Handle]: Record} = setmetatable({}, {__mode = "k"}) :: any
local slots: {[number]: {generation: number, live: boolean}} = {}
local session, active = 0, false
local api = {}
local function integer(value: number, lo: number, hi: number): number
    assert(value == math.floor(value) and value >= lo and value <= hi, "invalid resource integer")
    return value
end
local function ready()
    assert(active and session ~= 0, "resource operations require a configured init/update callback")
end
local function reserve(kind: string, format: number, channels: number): Handle
    ready()
    for i = 1, schema.maxSlots do
        local slot = slots[i]
        if not slot then slot = {generation = 1, live = false}; slots[i] = slot end
        if not slot.live and slot.generation <= 65535 then
            slot.live = true
            local handle = table.freeze({_resourceKind = kind}) :: any
            records[handle] = {session = session, id = slot.generation * 65536 + i, kind = kind, format = format, channels = channels}
            return handle
        end
    end
    error("resource slot capacity exceeded")
end
local function check(handle: Handle, kind: string): Record
    ready()
    local record = records[handle]
    assert(record and record.session == session and record.kind == kind, "wrong resource kind or stale session")
    local slot = slots[record.id % 65536]
    assert(slot and slot.live and slot.generation == math.floor(record.id / 65536), "stale resource generation")
    return record
end
local function emit(op: number, id: number, values: {number}?, bytes: buffer?)
    local args = buffer.create(if values then 32 else 0)
    if values then for i, value in values do buffer.writeu32(args, (i - 1) * 4, value) end end
    host.resource_emit(op, id, args, bytes or buffer.create(0))
end
local function destroy(handle: Handle, kind: string)
    local record = check(handle, kind)
    emit(if kind == "texture" then schema.op_destroy_texture else schema.op_destroy_sample, record.id)
    local slot = slots[record.id % 65536]
    slot.live = false; slot.generation += 1
end
local data = {}
function data.pixels(format: "index8" | "rgba8", width: number, height: number): PixelBuffer
    assert(format == "index8" or format == "rgba8", "unsupported pixel format")
    integer(width, 1, schema.maxImageAxis); integer(height, 1, schema.maxImageAxis)
    return table.freeze({format = format, width = width, height = height, bytes = buffer.create(width * height * (if format == "rgba8" then 4 else 1))})
end
function data.pcm(frames: number, channels: number): PCMBuffer
    integer(frames, 1, schema.maxPayload / 4); integer(channels, 1, 2)
    assert(frames * channels * 4 <= schema.maxPayload, "PCM staging capacity exceeded")
    return table.freeze({frames = frames, channels = channels, samples = buffer.create(frames * channels * 4)})
end
local gfx = {}
function gfx.texture(desc: TextureDesc): Texture
    assert(desc.format == "index8" or desc.format == "rgba8", "unsupported pixel format")
    integer(desc.width, 1, schema.maxImageAxis); integer(desc.height, 1, schema.maxImageAxis)
    local format = if desc.format == "rgba8" then schema.format_rgba8 else schema.format_index8
    local handle = reserve("texture", format, 0)
    emit(schema.op_create_texture, records[handle].id, {format, desc.width, desc.height})
    return handle :: Texture
end
function gfx.upload(target: Texture, rect: Rect, pixels: PixelBuffer, opts: Upload?)
    local record = check(target, "texture")
    local format = if pixels.format == "rgba8" then schema.format_rgba8 else schema.format_index8
    assert(record.format == format, "texture and pixel buffer formats differ")
    local bpp = if format == schema.format_rgba8 then 4 else 1
    integer(rect.x, 0, schema.maxImageAxis); integer(rect.y, 0, schema.maxImageAxis)
    integer(rect.width, 1, schema.maxImageAxis); integer(rect.height, 1, schema.maxImageAxis)
    local offset = integer(if opts then opts.offset_bytes or 0 else 0, 0, schema.maxPayload)
    local stride = integer(if opts then opts.stride_bytes or pixels.width * bpp else pixels.width * bpp, 0, schema.maxPayload)
    if stride == 0 then stride = pixels.width * bpp end
    emit(schema.op_write_texture, record.id, {rect.x, rect.y, rect.width, rect.height, offset, stride}, pixels.bytes)
end
function gfx.destroy(target: Texture) destroy(target, "texture") end
local audio = {}
function audio.write(target: Sample, range: FrameRange, pcm: PCMBuffer)
    local record = check(target, "sample")
    integer(range.first, 0, schema.maxResourceBytes / 4); integer(range.frames, 1, schema.maxPayload / 4)
    assert(pcm.channels == record.channels and pcm.frames == range.frames and buffer.len(pcm.samples) == pcm.frames * pcm.channels * 4, "PCM descriptor does not match buffer")
    emit(schema.op_write_sample, record.id, {range.first, range.frames}, pcm.samples)
end
function audio.sample(desc: SampleDesc, pcm: PCMBuffer?): Sample
    integer(desc.frames, 1, schema.maxResourceBytes / 4); integer(desc.channels, 1, 2); integer(desc.rate, 8000, 96000)
    assert(desc.frames * desc.channels * 4 <= schema.maxResourceBytes, "sample capacity exceeded")
    local handle = reserve("sample", schema.format_f32, desc.channels)
    emit(schema.op_create_sample, records[handle].id, {schema.format_f32, desc.frames, desc.channels, desc.rate})
    if pcm then audio.write(handle :: Sample, {first = 0, frames = pcm.frames}, pcm) end
    return handle :: Sample
end
function audio.destroy(target: Sample) destroy(target, "sample") end
function api._begin(tick: number)
    if tick == 0 then session = host.resource_session(); slots = {} end
    active = true
end
function api._end() active = false end
api.gfx = table.freeze(gfx)
api.audio = table.freeze(audio)
api.data = table.freeze(data)
return table.freeze(api)

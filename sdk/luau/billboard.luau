--!strict
local math3d = require("./math3d")
local schema = require("./resource_schema")

export type Desc = math3d.BillboardDesc

local function finite(value: number): boolean
    return value == value and math.abs(value) <= schema.max3dCoordinate
end

local function normalize(value: { number }): { number }
    local length = math.sqrt(value[1] ^ 2 + value[2] ^ 2 + value[3] ^ 2)
    assert(length > 0, "degenerate billboard camera basis")
    return { value[1] / length, value[2] / length, value[3] / length }
end

local function model(desc: Desc): math3d.Matrix
    assert(
        #desc.position == 3 and #desc.size == 2 and #desc.view == 16,
        "invalid billboard dimensions"
    )
    local pivot = desc.pivot or { 0, 0 }
    local rotation = desc.rotation or 0
    assert(#pivot == 2 and finite(rotation), "invalid billboard pivot or rotation")
    assert(
        desc.mode == nil or desc.mode == "facing" or desc.mode == "upright",
        "invalid billboard mode"
    )
    for _, value in desc.view do
        assert(finite(value), "invalid billboard view")
    end
    for _, value in desc.position do
        assert(finite(value), "invalid billboard position")
    end
    for _, value in desc.size do
        assert(finite(value) and value > 0, "invalid billboard size")
    end
    for _, value in pivot do
        assert(finite(value), "invalid billboard pivot")
    end
    local view = desc.view
    assert(
        view[4] == 0 and view[8] == 0 and view[12] == 0 and view[16] == 1,
        "billboard requires an affine camera view, without projection"
    )
    local right = { view[1], view[5], view[9] }
    local up = { view[2], view[6], view[10] }
    if desc.mode == "upright" then
        right[2] = 0
        up = { 0, 1, 0 }
    end
    right = normalize(right)
    local alignment = right[1] * up[1] + right[2] * up[2] + right[3] * up[3]
    for axis = 1, 3 do
        up[axis] -= right[axis] * alignment
    end
    up = normalize(up)
    local c, s = math.sin(rotation + math.pi / 2), math.sin(rotation)
    local result = math3d.identity()
    local normal = {
        right[2] * up[3] - right[3] * up[2],
        right[3] * up[1] - right[1] * up[3],
        right[1] * up[2] - right[2] * up[1],
    }
    for axis = 1, 3 do
        result[8 + axis] = normal[axis]
        local horizontal = (right[axis] * c + up[axis] * s) * desc.size[1]
        local vertical = (-right[axis] * s + up[axis] * c) * desc.size[2]
        result[axis], result[4 + axis] = horizontal, vertical
        result[12 + axis] = desc.position[axis] - horizontal * pivot[1] - vertical * pivot[2]
    end
    return result
end

type Vertex = { position: { number }, color: number, uv: { number } }

local function geometry<T>(create: ({ Vertex }, { number }) -> T): T
    return create({
        { position = { 0, 0, 0 }, color = 0xffffffff, uv = { 0, 1 } },
        { position = { 1, 0, 0 }, color = 0xffffffff, uv = { 1, 1 } },
        { position = { 1, 1, 0 }, color = 0xffffffff, uv = { 1, 0 } },
        { position = { 0, 1, 0 }, color = 0xffffffff, uv = { 0, 0 } },
    }, { 0, 2, 1, 0, 3, 2 })
end

return table.freeze({ model = model, geometry = geometry })

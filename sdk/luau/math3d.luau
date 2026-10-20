--!strict
export type Matrix = { number }
local api = {}
local rounding = buffer.create(4)
local function f32(x: number): number
    buffer.writef32(rounding, 0, x)
    return buffer.readf32(rounding, 0)
end
function api.identity(): Matrix
    return { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }
end
function api.multiply(a: Matrix, b: Matrix): Matrix
    local m = table.create(16, 0)
    for col = 0, 3 do
        for row = 0, 3 do
            local sum = 0
            for i = 0, 3 do
                sum += a[i * 4 + row + 1] * b[col * 4 + i + 1]
            end
            m[col * 4 + row + 1] = f32(sum)
        end
    end
    return m
end
function api.pose(x: number, y: number, z: number, yaw: number, scale: number): Matrix
    local c, s = f32(math.sin(yaw + math.pi / 2) * scale), f32(math.sin(yaw) * scale)
    return { c, 0, -s, 0, 0, f32(scale), 0, 0, s, 0, c, 0, f32(x), f32(y), f32(z), 1 }
end
function api.orthographic(
    left: number,
    right: number,
    bottom: number,
    top: number,
    near: number,
    far: number
): Matrix
    assert(right > left and top > bottom and far > near, "invalid orthographic bounds")
    return {
        f32(2 / (right - left)),
        0,
        0,
        0,
        0,
        f32(2 / (top - bottom)),
        0,
        0,
        0,
        0,
        f32(1 / (far - near)),
        0,
        f32(-(right + left) / (right - left)),
        f32(-(top + bottom) / (top - bottom)),
        f32(-near / (far - near)),
        1,
    }
end
function api.perspective(fovy: number, aspect: number, near: number, far: number): Matrix
    assert(
        fovy > 0 and fovy < math.pi and aspect > 0 and near > 0 and far > near,
        "invalid perspective bounds"
    )
    local s = math.sin(fovy / 2 + math.pi / 2) / math.sin(fovy / 2)
    return {
        f32(s / aspect),
        0,
        0,
        0,
        0,
        f32(s),
        0,
        0,
        0,
        0,
        f32(far / (far - near)),
        1,
        0,
        0,
        f32(-near * far / (far - near)),
        0,
    }
end
local function normalize(v: { number }): { number }
    local length = math.sqrt(v[1] ^ 2 + v[2] ^ 2 + v[3] ^ 2)
    assert(length > 0, "invalid camera direction")
    return { v[1] / length, v[2] / length, v[3] / length }
end
function api.look_at(eye: { number }, target: { number }): Matrix
    local z = normalize({ target[1] - eye[1], target[2] - eye[2], target[3] - eye[3] })
    local x = normalize({ z[3], 0, -z[1] })
    local y = { z[2] * x[3] - z[3] * x[2], z[3] * x[1] - z[1] * x[3], z[1] * x[2] - z[2] * x[1] }
    local function dot(a: { number }, b: { number }): number
        return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
    end
    return {
        f32(x[1]),
        f32(y[1]),
        f32(z[1]),
        0,
        f32(x[2]),
        f32(y[2]),
        f32(z[2]),
        0,
        f32(x[3]),
        f32(y[3]),
        f32(z[3]),
        0,
        f32(-dot(x, eye)),
        f32(-dot(y, eye)),
        f32(-dot(z, eye)),
        1,
    }
end
return table.freeze(api)

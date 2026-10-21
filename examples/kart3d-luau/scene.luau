--!strict
local byt = require("@bytorio")
local course = require("./course")
local g = byt.gfx3d
local COLORS = {
    0xff3445e8,
    0xff2789e8,
    0xff43b747,
    0xffe36c28,
    0xffcf7740,
    0xff5683dc,
    0xffdddddd,
    0xff62c8f5,
}
local vertices: { { position: { number }, color: number } } = {}
local indices: { number } = {}

local function triangle(a: { number }, b: { number }, c: { number }, color: number)
    local start = #vertices
    for _, p in { a, b, c } do
        table.insert(vertices, { position = p, color = color })
    end
    for _, index in { start, start + 1, start + 2 } do
        table.insert(indices, index)
    end
end

local function quad(a: { number }, b: { number }, c: { number }, d: { number }, color: number)
    local start = #vertices
    for _, p in { a, b, c, d } do
        table.insert(vertices, { position = p, color = color })
    end
    for _, index in { start, start + 1, start + 2, start, start + 2, start + 3 } do
        table.insert(indices, index)
    end
end
local function shade(color: number, factor: number): number
    local out = 0xff000000
    for _, shift in { 0, 8, 16 } do
        out += bit32.lshift(
            math.floor(bit32.band(bit32.rshift(color, shift), 255) * factor / 100),
            shift
        )
    end
    return out
end

-- Six broad facets keep distant trees, hills and clouds readable.
local function crown(
    x: number,
    y: number,
    z: number,
    w: number,
    h: number,
    d: number,
    color: number
)
    for side = 0, 5 do
        local angle = side * math.pi / 3
        local nextAngle = (side + 1) * math.pi / 3
        local a =
            { x + math.sin(angle + math.pi / 2) * w / 2, y + h * 0.45, z + math.sin(angle) * d / 2 }
        local b = {
            x + math.sin(nextAngle + math.pi / 2) * w / 2,
            y + h * 0.45,
            z + math.sin(nextAngle) * d / 2,
        }
        triangle(a, { x, y + h, z }, b, shade(color, 76 + side * 4))
        triangle(b, { x, y, z }, a, shade(color, 58 + side * 4))
    end
end

local function pyramid(
    x: number,
    y: number,
    z: number,
    w: number,
    h: number,
    d: number,
    color: number
)
    local a = { x - w / 2, y, z - d / 2 }
    local b = { x + w / 2, y, z - d / 2 }
    local c = { x + w / 2, y, z + d / 2 }
    local e = { x - w / 2, y, z + d / 2 }
    local tip = { x, y + h, z }
    triangle(a, tip, b, shade(color, 78))
    triangle(b, tip, c, shade(color, 92))
    triangle(c, tip, e, color)
    triangle(e, tip, a, shade(color, 66))
end

local function box(x: number, y: number, z: number, w: number, h: number, d: number, color: number)
    local a, b, c, e, top = x - w / 2, x + w / 2, z - d / 2, z + d / 2, y + h
    quad({ a, top, c }, { a, top, e }, { b, top, e }, { b, top, c }, color)
    quad({ a, y, c }, { b, y, c }, { b, top, c }, { a, top, c }, shade(color, 75))
    quad({ b, y, e }, { a, y, e }, { a, top, e }, { b, top, e }, shade(color, 88))
    quad({ a, y, e }, { a, y, c }, { a, top, c }, { a, top, e }, shade(color, 68))
    quad({ b, y, c }, { b, y, e }, { b, top, e }, { b, top, c }, shade(color, 82))
    quad({ a, y, c }, { a, y, e }, { b, y, e }, { b, y, c }, shade(color, 60))
end
local function finishMesh(): byt.Mesh
    local mesh = g.mesh(vertices, indices)
    table.clear(vertices)
    table.clear(indices)
    return mesh
end
local function edge(p: { number }, offset: number, lift: number?): { number }
    return { p[1] + p[5] * offset, p[2] + (lift or 0), p[3] - p[4] * offset }
end
local function strip(
    a: { number },
    b: { number },
    left: number,
    right: number,
    color: number,
    lift: number?
)
    quad(
        edge(a, left, lift),
        edge(b, left, lift),
        edge(b, right, lift),
        edge(a, right, lift),
        color
    )
end
local function create()
    local chunks: { byt.Mesh }, bodies: { byt.Mesh } = {}, {}
    for chunk = 0, 11 do
        for i = chunk * 8, chunk * 8 + 7 do
            local a, b = course[i + 1], course[(i + 1) % 96 + 1]
            strip(a, b, -5.5, 5.5, 0xff858689)
            local curb = if i % 2 == 0 then 0xffeeeef4 else 0xff4347da
            strip(a, b, -6.1, -5.5, curb)
            strip(a, b, 5.5, 6.1, curb)
            local grass = if i % 2 == 0 then 0xff399e58 else 0xff359452
            strip(a, b, -12, -6.1, grass)
            strip(a, b, 6.1, 12, grass)
            if i % 4 < 2 then
                strip(a, b, -0.08, 0.08, 0xffcfe5ec, 0.025)
            end
            if i % 8 == 4 then
                local p = edge(a, 9)
                box(p[1], p[2], p[3], 0.55, 2, 0.55, 0xff486283)
                crown(p[1], p[2] + 1.3, p[3], 3.8, 4.0, 3.8, 0xff38a367)
            end
            if i % 4 == 0 then
                for _, side in { -7.2, 7.2 } do
                    local p = edge(a, side)
                    box(p[1], p[2], p[3], 0.28, 0.8, 0.28, 0xffe8f0f1)
                end
            end
            if i == 0 then
                for x = 0, 9 do
                    strip(
                        a,
                        b,
                        -5.5 + x * 1.1,
                        -5.5 + (x + 1) * 1.1,
                        if x % 2 == 0 then 0xffeeeeee else 0xff25252c,
                        0.03
                    )
                end
                local p, q = edge(a, -6.5), edge(a, 6.5)
                box(p[1], p[2], p[3], 0.5, 4.5, 0.5, 0xffeeeeee)
                box(q[1], q[2], q[3], 0.5, 4.5, 0.5, 0xffeeeeee)
                box(a[1], a[2] + 4, a[3], 0.7, 0.7, 14, 0xff4894ec)
            end
        end
        table.insert(chunks, finishMesh())
    end
    quad({ -160, -3, -160 }, { -160, -3, 160 }, { 160, -3, 160 }, { 160, -3, -160 }, 0xff39834b)
    for hill = 0, 3 do
        local angle = hill * math.pi / 2 + 0.35
        crown(math.sin(angle) * 16, -3, math.sin(angle + math.pi / 2) * 16, 27, 10, 22, 0xff4ca46d)
    end
    for cloud = 0, 5 do
        local angle = cloud * math.pi / 3
        crown(
            math.sin(angle) * 68,
            19 + cloud % 2 * 3,
            math.sin(angle + math.pi / 2) * 68,
            19,
            4,
            7,
            0xfffaf5ec
        )
    end
    -- An original hilltop keep is visible from several bends of the course.
    box(0, 1, 0, 9, 8, 7, 0xffb5c5cb)
    box(0, 8, 0, 4, 5, 4, 0xffc8d4d8)
    pyramid(0, 13, 0, 5.2, 3.2, 5.2, 0xff3447c5)
    for _, side in { -1, 1 } do
        box(side * 5, 1, 1, 3, 9, 3, 0xffb5c5cb)
        pyramid(side * 5, 10, 1, 4, 3.5, 4, 0xff3447c5)
        box(side * 2.7, 9, 0, 1.3, 1.2, 7, 0xffd3dce0)
        quad(
            { side * 5 - 0.35, 6, 2.51 },
            { side * 5 + 0.35, 6, 2.51 },
            { side * 5 + 0.35, 7.5, 2.51 },
            { side * 5 - 0.35, 7.5, 2.51 },
            0xff424750
        )
    end
    quad({ -1.1, 1, 3.51 }, { 1.1, 1, 3.51 }, { 1.1, 4.4, 3.51 }, { -1.1, 4.4, 3.51 }, 0xff405c78)
    triangle({ 0, 16.1, 0 }, { 0, 17.8, 0 }, { 2.5, 17.1, 0 }, 0xff3a4de0)
    local ground = finishMesh()
    for index, color in COLORS do
        local i = index - 1
        box(0, 0.26, 0, 1.6, 0.36, 2.25, color)
        box(0, 0.58, 0.63, 1.35, 0.3, 0.75, color)
        box(0, 0.29, -1.12, 1.85, 0.26, 0.22, 0xff363a43)
        box(0, 0.58, -0.44, 0.95, 0.48, 0.3, 0xff34313b)
        box(0, 0.79, -0.12, 0.65, 0.58, 0.55, shade(color, 62))
        box(0, 1.3, -0.12, 0.68, 0.48, 0.63, 0xff92bce9)
        quad(
            { -0.33, 1.25, 0.05 },
            { -0.58, 0.96, 0.48 },
            { -0.43, 0.88, 0.48 },
            { -0.18, 1.14, 0.05 },
            0xff92bce9
        )
        quad(
            { 0.18, 1.14, 0.05 },
            { 0.43, 0.88, 0.48 },
            { 0.58, 0.96, 0.48 },
            { 0.33, 1.25, 0.05 },
            0xff92bce9
        )
        if i % 4 == 0 then
            crown(0, 1.44, -0.2, 1.15, 0.65, 1.05, 0xffad3b65)
            for spike = 0, 3 do
                local angle = spike * math.pi / 2
                pyramid(
                    math.sin(angle) * 0.38,
                    1.85,
                    -0.2 + math.sin(angle + math.pi / 2) * 0.35,
                    0.46,
                    0.43,
                    0.46,
                    0xffbd4c78
                )
            end
            quad(
                { -0.38, 1.37, -0.43 },
                { -0.79, 0.83, -1.28 },
                { 0, 0.69, -1.08 },
                { 0.15, 1.29, -0.44 },
                0xff2635d8
            )
            quad(
                { 0.15, 1.29, -0.44 },
                { 0, 0.69, -1.08 },
                { 0.72, 0.77, -1.18 },
                { 0.38, 1.37, -0.43 },
                0xff394df8
            )
        elseif i % 4 == 1 then
            crown(0, 1.42, -0.17, 1.03, 0.62, 0.9, 0xff2989de)
            pyramid(-0.32, 1.86, -0.1, 0.36, 0.48, 0.42, 0xff2473bf)
            pyramid(0.32, 1.86, -0.1, 0.36, 0.48, 0.42, 0xff2473bf)
            pyramid(0.35, 0.72, -0.93, 0.48, 0.65, 0.6, 0xffdde8ef)
        elseif i % 4 == 2 then
            box(0, 1.49, -0.17, 0.96, 0.5, 0.83, 0xff46b358)
            pyramid(0, 1.99, -0.17, 0.18, 0.36, 0.18, 0xff55dfb5)
            quad(
                { -0.3, 1.6, 0.251 },
                { 0.3, 1.6, 0.251 },
                { 0.3, 1.8, 0.251 },
                { -0.3, 1.8, 0.251 },
                0xffd9f249
            )
        else
            crown(0, 1.4, -0.17, 1.08, 0.75, 0.98, 0xffe67835)
            pyramid(0, 2.01, -0.17, 0.18, 0.32, 0.65, 0xff384ddf)
            quad(
                { -0.34, 1.53, 0.31 },
                { 0.34, 1.53, 0.31 },
                { 0.34, 1.76, 0.31 },
                { -0.34, 1.76, 0.31 },
                0xff493d2a
            )
        end
        table.insert(bodies, finishMesh())
    end
    for side = 0, 5 do
        local angle = side * math.pi / 3
        local nextAngle = (side + 1) * math.pi / 3
        local y, z = math.sin(angle) * 0.39, math.sin(angle + math.pi / 2) * 0.39
        local ny, nz = math.sin(nextAngle) * 0.39, math.sin(nextAngle + math.pi / 2) * 0.39
        quad(
            { -0.24, y, z },
            { 0.24, y, z },
            { 0.24, ny, nz },
            { -0.24, ny, nz },
            if side % 2 == 0 then 0xff29272b else 0xff38363a
        )
        local spoke = if side % 2 == 0 then 0xffaebec9 else 0xff444750
        triangle({ -0.241, 0, 0 }, { -0.241, y, z }, { -0.241, ny, nz }, spoke)
        triangle({ 0.241, 0, 0 }, { 0.241, ny, nz }, { 0.241, y, z }, spoke)
    end
    local wheel = finishMesh()
    box(0, 0, 0, 0.65, 0.65, 0.65, 0xff52dcf5)
    box(0, 0.12, 0.34, 0.2, 0.4, 0.02, 0xffeeeeee)
    local pickup = finishMesh()
    box(0, 0, 0, 0.13, 0.15, 0.4, 0xff42cfff)
    local spark = finishMesh()
    quad(
        { -1.1, 0.025, -1.3 },
        { -1.1, 0.025, 1.3 },
        { 1.1, 0.025, 1.3 },
        { 1.1, 0.025, -1.3 },
        0xff4c4a46
    )
    return {
        chunks = chunks,
        bodies = bodies,
        ground = ground,
        wheel = wheel,
        pickup = pickup,
        spark = spark,
        shadow = finishMesh(),
    }
end
local function sample(distance: number, lane: number?): ({ number }, number)
    local at = distance % 98304
    local index = math.floor(at / 1024)
    local a, b = course[index + 1], course[(index + 1) % 96 + 1]
    local fraction = (at % 1024) / 1024
    local p = {
        a[1] + (b[1] - a[1]) * fraction,
        a[2] + (b[2] - a[2]) * fraction,
        a[3] + (b[3] - a[3]) * fraction,
    }
    p[1] += (a[5] + (b[5] - a[5]) * fraction) * (lane or 0) / 128
    p[3] -= (a[4] + (b[4] - a[4]) * fraction) * (lane or 0) / 128
    local turn = b[7] - a[7]
    if turn > math.pi then
        turn -= 2 * math.pi
    end
    if turn < -math.pi then
        turn += 2 * math.pi
    end
    return p, a[7] + turn * fraction
end
return { create = create, sample = sample, colors = COLORS }

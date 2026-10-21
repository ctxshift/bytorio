--!strict
local byt = require("@bytorio")
local kart = require("./imported/model")
local tree = require("./tree/model")
local atlas = require("./atlas")
local course = require("./course")
local scene = require("./scene")
local race = require("./race")
local g, gfx, data = byt.gfx3d, byt.gfx, byt.data

local PARTICLE_CAPACITY = 48
local PARTICLE_LIFETIME = 30
local DETAIL_NEAR, DETAIL_FAR = 22, 26
-- Match an Odin Matrix literal's f32 storage before composing its transforms.
local SHADOW_MODEL =
    g.multiply(g.identity(), { 2.4, 0, 0, 0, 0, 0, 2.8, 0, 0, -1, 0, 0, -1.2, 0.028, -1.4, 1 })
type Particle = { position: { number }, age: number, glow: boolean }
local asset: kart.Instance
local treeAsset: tree.Instance
local kartSurfaces: { byt.Material } = {}
local locals: { { number } }
local quad: byt.TexturedMesh
local dust: { byt.Material } = {}
local boost: { byt.Material } = {}
local shadow: byt.Material
local flowers: byt.Material
local asphalt: byt.Material
local roads: { byt.TexturedMesh } = {}
local particles: { Particle } = {}
local near: { boolean } = {}
local cursor = 1
local detail = 0

local function makeArt(kind: number, fade: number?): byt.Material
    local pixels = data.pixels("rgba8", 8, 8)
    for y = 0, 7 do
        for x = 0, 7 do
            local dx, dy = x * 2 - 7, y * 2 - 7
            local radius = dx * dx + dy * dy
            local color: number = 0
            if kind <= 2 then
                local alpha: number = math.floor(math.max(0, 64 - radius) * (4 - (fade or 0)) / 4)
                if kind == 2 then
                    alpha = math.floor(alpha / 2)
                end
                local red: number = math.floor(alpha * 3 / 4)
                local green: number = math.floor(alpha * 2 / 3)
                local blue: number = math.floor(alpha / 2)
                if kind == 1 then
                    red = math.floor(alpha / 4)
                    green = math.floor(alpha * 3 / 4)
                    blue = alpha
                end
                if kind == 2 then
                    red = math.floor(alpha / 8)
                    green = math.floor(alpha / 8)
                    blue = math.floor(alpha / 8)
                end
                color = bit32.bor(
                    red,
                    bit32.lshift(green, 8),
                    bit32.lshift(blue, 16),
                    bit32.lshift(alpha, 24)
                )
            elseif kind == 3 then
                if (x == 3 or x == 4) and y >= 3 then
                    color = 0xff43924d
                end
                if radius <= 12 then
                    color = 0xffdcefff
                end
                if radius <= 2 then
                    color = 0xff35caff
                end
            else
                local value = 122 + (x * 13 + y * 7) % 5
                color = 0xff000000 + value + (value + 2) * 256 + (value + 5) * 65536
            end
            buffer.writeu32(pixels.bytes, (y * 8 + x) * 4, color)
        end
    end
    local texture = gfx.texture({ format = "rgba8", width = 8, height = 8 })
    gfx.upload(texture, { x = 0, y = 0, width = 8, height = 8 }, pixels)
    if kind == 3 then
        return g.cutout_material(texture)
    end
    if kind == 4 then
        return g.material(texture, { address_u = "repeat", address_v = "repeat" })
    end
    return g.effect_material(texture, { blend = if kind == 1 then "additive" else "alpha" })
end

local function edge(point: { number }, side: number): { number }
    return { point[1] + point[5] * side, point[2], point[3] - point[4] * side }
end

local function init()
    asset = kart.create()
    treeAsset = tree.create()
    kartSurfaces = { asset.materials[1] }
    for index = 2, 8 do
        local pixels = data.pixels("rgba8", 16, 16)
        for at, original in atlas do
            local color = original
            local x, y = (at - 1) % 16, math.floor((at - 1) / 16)
            if y < 4 and x < 8 then
                local base = scene.colors[index]
                local factor = if x < 4 then 100 else 65
                color = 0xff000000
                for channel = 0, 2 do
                    local value = bit32.band(bit32.rshift(base, channel * 8), 255)
                    color += math.floor(value * factor / 100) * 2 ^ (channel * 8)
                end
            end
            buffer.writeu32(pixels.bytes, (at - 1) * 4, color)
        end
        local texture = gfx.texture({ format = "rgba8", width = 16, height = 16 })
        gfx.upload(texture, { x = 0, y = 0, width = 16, height = 16 }, pixels)
        kartSurfaces[index] = g.material(texture)
    end
    locals = kart.local_transforms()
    detail, cursor = 0, 1
    particles, near = {}, {}
    for i = 1, PARTICLE_CAPACITY do
        particles[i] = { position = { 0, 0, 0 }, age = PARTICLE_LIFETIME, glow = false }
    end
    for i = 1, 8 do
        near[i] = false
    end
    quad = g.billboard()
    for i = 1, 4 do
        dust[i], boost[i] = makeArt(0, i - 1), makeArt(1, i - 1)
    end
    shadow, flowers, asphalt = makeArt(2), makeArt(3), makeArt(4)
    roads = {}
    for chunk = 0, 11 do
        local vertices, indices = {}, {}
        for segment = 0, 7 do
            local i = chunk * 8 + segment
            local a, b = course[i + 1], course[(i + 1) % 96 + 1]
            local points = { edge(a, -5.5), edge(a, 5.5), edge(b, 5.5), edge(b, -5.5) }
            local uvs = { { 0, 0 }, { 4, 0 }, { 4, 1 }, { 0, 1 } }
            for corner, p in points do
                table.insert(vertices, {
                    position = { p[1], p[2] + 0.012, p[3] },
                    color = 0xffffffff,
                    uv = uvs[corner],
                })
            end
            for _, index in { 0, 2, 1, 0, 3, 2 } do
                table.insert(indices, segment * 4 + index)
            end
        end
        roads[chunk + 1] = g.textured_mesh(vertices, indices)
    end
end

local function update(s: race.State)
    if s.tick <= 1 then
        for _, particle in particles do
            particle.age = PARTICLE_LIFETIME
        end
        cursor = 1
    end
    local player = scene.sample(s.distance, s.lateral)
    for index = 1, 8 do
        local distance = if index == 1 then s.distance else s.rivals[index - 1]
        local lane = if index == 1 then s.lateral else ((index - 2) % 3 - 1) * 370
        local p = scene.sample(distance, lane)
        local separation = (p[1] - player[1]) ^ 2 + (p[3] - player[3]) ^ 2
        if separation < DETAIL_NEAR * DETAIL_NEAR then
            near[index] = true
        end
        if separation > DETAIL_FAR * DETAIL_FAR then
            near[index] = false
        end
    end
    for _, particle in particles do
        if particle.age < PARTICLE_LIFETIME then
            particle.age += 1
            particle.position[2] += 1 / 128
        end
    end
    if
        s.tick % 3 == 0
        and s.speed > 40
        and (s.boost > 0 or math.abs(s.lateral) > 680 or s.drift ~= 0)
    then
        local side = if math.floor(s.tick / 3) % 2 == 0 then -80 else 80
        local p = scene.sample(s.distance - 300, s.lateral + side)
        p[2] += 0.3
        local particle = particles[cursor]
        particle.position, particle.age, particle.glow = p, 0, s.boost > 0 or s.charge > 0
        cursor = cursor % PARTICLE_CAPACITY + 1
    end
end

local function world(pass: byt.Pass, chunk: number, s: race.State, view: { number })
    for offset = -3, 3 do
        g.draw_textured(pass, roads[(chunk + offset + 12) % 12 + 1], asphalt)
    end
    local segment = math.floor(s.distance / 1024)
    for offset = -3, 6 do
        local at = ((math.floor(segment / 4) + offset) * 4 + 96) % 96
        for _, side in { -6.8, 6.8 } do
            g.draw_billboard(pass, quad, flowers, {
                position = edge(course[at + 1], side),
                size = { 0.7, 0.7 },
                pivot = { 0.5, 0 },
                view = view,
                mode = "upright",
            })
        end
        if at % 8 == 4 then
            local p = edge(course[at + 1], -9)
            tree.draw(pass, treeAsset, g.pose(p[1], p[2], p[3], 0, 1))
        end
    end
end

local function drawKart(
    pass: byt.Pass,
    index: number,
    model: { number },
    distance: number,
    heading: number,
    tick: number,
    rotationX: (number) -> { number }
)
    local detailed = detail == 2 or (detail == 0 and near[index])
    local surface = kartSurfaces[index]
    g.draw_textured(pass, asset.meshes[1], surface, model)
    local driver = g.multiply(model, g.pose(0, 0, 0, heading / 2048, 1))
    g.draw_textured(pass, asset.meshes[2], surface, driver)
    local cape =
        g.multiply(driver, g.multiply(locals[3], g.pose(0, 0, 0, math.sin(tick / 9) * 0.08, 1)))
    g.draw_textured(pass, asset.meshes[3], surface, cape)
    if detailed then
        g.draw_textured(pass, asset.meshes[5], surface, model)
        g.draw_textured(pass, asset.meshes[6], surface, driver)
    end
    local spin = rotationX((distance % 4096) / 256)
    for node = 4, 7 do
        local steer = g.pose(0, 0, 0, if node < 6 then heading / 256 else 0, 1)
        local wheel = g.multiply(model, g.multiply(locals[node], g.multiply(steer, spin)))
        g.draw_textured(pass, asset.meshes[if detailed then 7 else 4], surface, wheel)
    end
end

local function effects(
    pass: byt.Pass,
    s: race.State,
    view: { number },
    rotationX: (number) -> { number }
)
    for index = 1, 8 do
        local distance = if index == 1 then s.distance else s.rivals[index - 1]
        local lane = if index == 1 then s.lateral else ((index - 2) % 3 - 1) * 370
        local p, yaw = scene.sample(distance, lane)
        local pitch = rotationX(course[math.floor((distance % 98304) / 1024) + 1][8])
        g.draw_textured(
            pass,
            quad,
            shadow,
            g.multiply(g.pose(p[1], p[2], p[3], yaw, 1), g.multiply(pitch, SHADOW_MODEL))
        )
    end
    local order, depths = {}, {}
    for index, particle in particles do
        if particle.age >= PARTICLE_LIFETIME then
            continue
        end
        local p = particle.position
        depths[index] = view[3] * p[1] + view[7] * p[2] + view[11] * p[3]
        table.insert(order, index)
        local j = #order
        while j > 1 and depths[order[j]] > depths[order[j - 1]] do
            order[j], order[j - 1] = order[j - 1], order[j]
            j -= 1
        end
    end
    for _, index in order do
        local particle = particles[index]
        local fade = math.min(3, math.floor(particle.age * 4 / PARTICLE_LIFETIME)) + 1
        local surface = if particle.glow then boost[fade] else dust[fade]
        local size = 0.4 + particle.age / 50
        g.draw_billboard(pass, quad, surface, {
            position = particle.position,
            size = { size, size },
            pivot = { 0.5, 0.5 },
            view = view,
        })
    end
end

local function cycleDetail()
    detail = (detail + 1) % 3
end

local function detailName(): string
    return ({ "AUTO LOD", "LOW DETAIL", "HIGH DETAIL" })[detail + 1]
end

local function inspect(): { number }
    local active, close = 0, 0
    for _, particle in particles do
        if particle.age < PARTICLE_LIFETIME then
            active += 1
        end
    end
    for _, value in near do
        if value then
            close += 1
        end
    end
    return { detail, active, close }
end

return {
    init = init,
    update = update,
    world = world,
    kart = drawKart,
    effects = effects,
    cycle_detail = cycleDetail,
    detail_name = detailName,
    inspect = inspect,
}

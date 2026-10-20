--!strict
local console = require("@console")
local decode = require("./console-decode")
local gfx, g = console.gfx, console.gfx3d

-- Populated by console-build.mjs from the preserved scene's surface field.
local SCENE_ENCODED = ""
local SCENE_BYTES = 0

local FACE_BYTES = 13
local FACES_PER_CHUNK = 512
local BACKGROUND = 0xffc5ad94
local meshes: { console.Mesh } = {}
local rabbit: console.Mesh
local depthLow: console.Depth
local depthHigh: console.Depth
local camera: console.Camera
local loaded, tick, faceOffset, worldFaces, rabbitFaces = 0, 0, 0, 0, 0
local bytes: buffer
local decodeStep: () -> buffer?
local decoding = true
local high = false
local walkOffset = 0
local WALK_WIDTH, WALK_HEIGHT = 157, 137
local rabbitX, rabbitY, rabbitZ, rabbitAngle = -4, 8, 19, 0
local yaw, panX, panZ = 0, 0, 0
local qualificationReplay, cameraReady = false, false
local lastProjection: { number }? = nil
type Vertex = { position: { number }, color: number }
local vertexPool: { Vertex } = {}
local FORWARD_INDICES = { 0, 1, 2, 0, 2, 3 }
local REVERSE_INDICES = { 0, 2, 1, 0, 3, 2 }
local matrixRounding = buffer.create(4)

local function signed16(at: number): number
    return buffer.readi16(bytes, at)
end

local function upload(first: number, count: number): console.Mesh
    local vertices: { Vertex } = {}
    local indices: { number } = {}
    for i = first, first + count - 1 do
        local at = faceOffset + i * FACE_BYTES
        local tag = buffer.readu8(bytes, at)
        local axis = tag % 4 + 1
        local axisA = if axis == 1 then 2 else 1
        local axisB = if axis == 3 then 2 else 3
        local plane, x, y = signed16(at + 1), signed16(at + 3), signed16(at + 5)
        local width, height = buffer.readu16(bytes, at + 7), buffer.readu16(bytes, at + 9)
        local color = buffer.readu32(bytes, 12 + buffer.readu16(bytes, at + 11) * 4)
        local base = #vertices
        for corner = 0, 3 do
            local slot = base + corner + 1
            local vertex = vertexPool[slot]
            if not vertex then
                vertex = { position = { 0, 0, 0 }, color = color }
                vertexPool[slot] = vertex
            end
            local p = vertex.position
            p[axis] = plane
            p[axisA] = x + (if corner == 1 or corner == 2 then width else 0)
            p[axisB] = y + (if corner >= 2 then height else 0)
            vertex.color = color
            vertices[slot] = vertex
        end
        local reverse = (tag >= 4) ~= (axis == 2)
        for _, index in (if reverse then REVERSE_INDICES else FORWARD_INDICES) do
            table.insert(indices, base + index)
        end
    end
    return g.mesh(vertices, indices)
end

local function resetMotion()
    rabbitX, rabbitY, rabbitZ, rabbitAngle = -4, 8, 19, 0
    yaw, panX, panZ = 0, 0, 0
end

local function walkHeight(x: number, z: number): number
    local ix, iz = math.floor(x + 0.5) + 78, math.floor(z + 0.5) + 68
    if ix < 0 or ix >= WALK_WIDTH or iz < 0 or iz >= WALK_HEIGHT then
        return -1
    end
    return buffer.readu8(bytes, walkOffset + iz * WALK_WIDTH + ix) - 1
end

local function moveRabbit(x: number, z: number)
    local height = walkHeight(x, z)
    if height < 0 or math.abs(height - rabbitY) > 2 then
        return
    end
    for dx = -1, 1, 2 do
        for dz = -1, 1, 2 do
            local edge = walkHeight(x + dx, z + dz)
            if edge < 0 or math.abs(edge - height) > 2 then
                return
            end
        end
    end
    rabbitX, rabbitY, rabbitZ = x, height, z
end

local function axis(positive: console.Button, negative: console.Button): number
    return (if console.button(positive) then 1 else 0) - (if console.button(negative) then 1 else 0)
end

local function updateControls(dt: number)
    if console.pressed("reset") then
        resetMotion()
        console.debug_position(rabbitX, rabbitZ)
    end
    yaw += dt * axis("rotate_right", "rotate_left") * 0.7
    yaw -= math.floor((yaw + math.pi) / (2 * math.pi)) * 2 * math.pi
    panX = math.clamp(panX + dt * axis("pan_right", "pan_left") * 7, -12, 12)
    panZ = math.clamp(panZ + dt * axis("pan_down", "pan_up") * 7, -12, 12)
    local dx, dz = axis("move_right", "move_left"), axis("move_down", "move_up")
    local length = math.sqrt(dx * dx + dz * dz)
    if length == 0 then
        return
    end
    dx, dz = dx / length, dz / length
    local s, c = math.sin(yaw), math.sin(yaw + math.pi / 2)
    local fx = -0.09692560046268578 * c - 0.8077133371890481 * s
    local fz = 0.09692560046268578 * s - 0.8077133371890481 * c
    local horizontal = math.sqrt(fx * fx + fz * fz)
    local mx, mz = (-fz * dx - fx * dz) / horizontal, (fx * dx - fz * dz) / horizontal
    moveRabbit(rabbitX + mx * dt * 12, rabbitZ)
    moveRabbit(rabbitX, rabbitZ + mz * dt * 12)
    local sign = if dx < 0 then -1 elseif dx > 0 then 1 else 0
    local facing = if dz == 0
        then sign * math.pi / 2
        elseif dz > 0 then sign * math.pi / 4
        elseif dx ~= 0 then sign * 3 * math.pi / 4
        else math.pi
    rabbitAngle = 0.11942892601833846 + yaw + facing
end

local function updateCamera()
    local angle = if qualificationReplay
        then (if console.button("right") then tick * 0.004 else 0)
        else yaw
    local s, c = math.sin(angle), math.sin(angle + math.pi / 2)
    local fx = -0.09692560046268578 * c - 0.8077133371890481 * s
    local fy = -0.5815536027761147
    local fz = 0.09692560046268578 * s - 0.8077133371890481 * c
    local length = math.sqrt(fx * fx + fz * fz)
    local rx, rz = -fz / length, fx / length
    local ux, uy, uz = -rz * fy, rz * fx - rx * fz, rx * fy
    local tx = if qualificationReplay
        then (if console.button("left") then tick * 0.07 else 0)
        else panX + (rabbitX + 4) * 0.3
    local tz = if qualificationReplay then 0 else panZ + (rabbitZ - 19) * 0.3
    local view = {
        rx,
        ux,
        fx,
        0,
        0,
        uy,
        fy,
        0,
        rz,
        uz,
        fz,
        0,
        -rx * tx - rz * tz,
        -ux * tx - uy * 24 - uz * tz,
        300 - fx * tx - fy * 24 - fz * tz,
        1,
    }
    -- Match the typed Odin matrix's f32 inputs before matrix multiplication.
    for i, value in view do
        buffer.writef32(matrixRounding, 0, value)
        view[i] = buffer.readf32(matrixRounding, 0)
    end
    local projection = g.multiply(g.orthographic(-90, 90, -50.625, 50.625, 0.1, 1000), view)
    local previous = lastProjection
    if cameraReady and previous then
        local same = true
        for i, value in projection do
            if previous[i] ~= value then
                same = false
                break
            end
        end
        if same then
            return
        end
    end
    if cameraReady then
        g.destroy(camera)
    end
    camera = g.camera({
        view_projection = projection,
        ambient = 1,
        fog_color = BACKGROUND,
        fog_start = 0.999,
        fog_end = 1,
    })
    lastProjection, cameraReady = projection, true
end

return {
    init = function()
        decodeStep = decode(SCENE_ENCODED, SCENE_BYTES)
        decoding = true
        worldFaces, rabbitFaces = 0, 0
        loaded, tick, meshes = 0, 0, {}
        vertexPool = {}
        resetMotion()
        qualificationReplay, cameraReady, lastProjection = false, false, nil
        depthLow, depthHigh = g.depth(320, 180), g.depth(640, 360)
        updateCamera()
    end,
    update = function(dt: number)
        qualificationReplay = console.all_buttons() == console.buttons()
            and bit32.band(console.buttons(), 15) ~= 0
        high = console.button("action")
        console.display(if high then 640 else 320, if high then 360 else 180)
        if decoding then
            local result = decodeStep()
            if result then
                bytes = result
                worldFaces, rabbitFaces = buffer.readu32(bytes, 0), buffer.readu32(bytes, 4)
                faceOffset = 12 + buffer.readu32(bytes, 8) * 4
                walkOffset = faceOffset + (worldFaces + rabbitFaces) * FACE_BYTES
                assert(buffer.len(bytes) == walkOffset + WALK_WIDTH * WALK_HEIGHT)
                decoding = false
                decodeStep = function(): buffer?
                    return nil
                end
            end
            return
        end
        if loaded < worldFaces then
            local count = math.min(FACES_PER_CHUNK, worldFaces - loaded)
            table.insert(meshes, upload(loaded, count))
            loaded += count
        elseif loaded == worldFaces then
            rabbit = upload(worldFaces, rabbitFaces)
            loaded += rabbitFaces
            vertexPool = {}
        else
            tick += 1
            if not qualificationReplay then
                updateControls(dt)
            end
            console.debug_position(rabbitX, rabbitZ)
        end
        updateCamera()
    end,
    draw = function()
        local screen = gfx.screen()
        local pass = gfx.begin_pass(screen, { clear = true, color = BACKGROUND })
        if loaded > worldFaces then
            g.bind(pass, if high then depthHigh else depthLow, camera)
            for _, mesh in meshes do
                g.draw(pass, mesh)
            end
            if qualificationReplay then
                local step = if console.button("up") then math.sin(tick * 0.03) * 2 else 0
                g.draw(pass, rabbit, g.pose(-4 + step, 8, 19, 0, 1))
            else
                g.draw(pass, rabbit, g.pose(rabbitX, rabbitY, rabbitZ, rabbitAngle, 1))
            end
        end
        gfx.end_pass(pass)
        gfx.present(screen)
    end,
}

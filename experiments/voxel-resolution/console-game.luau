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

local function updateCamera()
    local yaw = if console.button("right") then tick * 0.004 else 0
    local s, c = math.sin(yaw), math.sin(yaw + math.pi / 2)
    local fx = -0.09692560046268578 * c - 0.8077133371890481 * s
    local fy = -0.5815536027761147
    local fz = 0.09692560046268578 * s - 0.8077133371890481 * c
    local length = math.sqrt(fx * fx + fz * fz)
    local rx, rz = -fz / length, fx / length
    local ux, uy, uz = -rz * fy, rz * fx - rx * fz, rx * fy
    local tx = if console.button("left") then tick * 0.07 else 0
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
        -rx * tx,
        -ux * tx - uy * 24,
        300 - fx * tx - fy * 24,
        1,
    }
    -- Match the typed Odin matrix's f32 inputs before matrix multiplication.
    for i, value in view do
        buffer.writef32(matrixRounding, 0, value)
        view[i] = buffer.readf32(matrixRounding, 0)
    end
    camera = g.camera({
        view_projection = g.multiply(g.orthographic(-90, 90, -50.625, 50.625, 0.1, 1000), view),
        ambient = 1,
        fog_color = BACKGROUND,
        fog_start = 0.999,
        fog_end = 1,
    })
end

return {
    init = function()
        decodeStep = decode(SCENE_ENCODED, SCENE_BYTES)
        decoding = true
        worldFaces, rabbitFaces = 0, 0
        loaded, tick, meshes = 0, 0, {}
        vertexPool = {}
        depthLow, depthHigh = g.depth(320, 180), g.depth(640, 360)
        updateCamera()
    end,
    update = function()
        high = console.button("action")
        console.display(if high then 640 else 320, if high then 360 else 180)
        if decoding then
            local result = decodeStep()
            if result then
                bytes = result
                worldFaces, rabbitFaces = buffer.readu32(bytes, 0), buffer.readu32(bytes, 4)
                faceOffset = 12 + buffer.readu32(bytes, 8) * 4
                assert(buffer.len(bytes) == faceOffset + (worldFaces + rabbitFaces) * FACE_BYTES)
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
        end
        g.destroy(camera)
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
            local step = if console.button("up") then math.sin(tick * 0.03) * 2 else 0
            g.draw(pass, rabbit, g.pose(-4 + step, 8, 19, 0, 1))
        end
        gfx.end_pass(pass)
        gfx.present(screen)
    end,
}

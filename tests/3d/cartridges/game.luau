--!strict
local byt = require("@bytorio")
local gfx, g = byt.gfx, byt.gfx3d
local room: byt.Voxel
local prop: byt.Voxel
local checker: byt.Voxel
local actors: { byt.Voxel } = {}
local depthLow: byt.Depth
local depthHigh: byt.Depth
local ortho: byt.Camera
local perspective: byt.Camera
local pyramid: byt.Mesh
local tick = 0
local BACKGROUND = 0xff291b16
return {
    init = function()
        assert(byt.capabilities().profile == 3)
        tick = 0
        byt.display(320, 180)
        depthLow = g.depth(320, 180)
        depthHigh = g.depth(640, 360)
        local colors = buffer.create(1024)
        for i, color in
            {
                0xff699047,
                0xff735e54,
                0xff977c63,
                0xff55b8fa,
                0xffd2d7ee,
                0xffde8d44,
                0xff754ed3,
                0xffa5e5ff,
            }
        do
            buffer.writeu32(colors, i * 4, color)
        end
        local palette = gfx.palette(colors)
        local cells = buffer.create(12 * 6 * 12)
        for z = 0, 11 do
            for y = 0, 5 do
                for x = 0, 11 do
                    local cell = 0
                    if y == 0 then
                        cell = 1
                    end
                    if (x == 0 or z == 11) and y < 5 then
                        cell = 2 + (x + z + y) % 2
                    end
                    if z == 11 and (x == 5 or x == 6) and y > 0 and y < 4 then
                        cell = 0
                    end
                    buffer.writeu8(cells, (z * 6 + y) * 12 + x, cell)
                end
            end
        end
        room = g.voxel(12, 6, 12, palette, cells)
        local block = buffer.create(4 * 4 * 4)
        for i = 0, 63 do
            buffer.writeu8(block, i, 4 + i % 3)
        end
        prop = g.voxel(4, 4, 4, palette, block)
        local noise = buffer.create(16 * 16 * 16)
        for z = 0, 15 do
            for y = 0, 15 do
                for x = 0, 15 do
                    buffer.writeu8(
                        noise,
                        (z * 16 + y) * 16 + x,
                        if (x + y + z) % 2 == 0 then 4 + (x + y + z) % 3 else 0
                    )
                end
            end
        end
        checker = g.voxel(16, 16, 16, palette, noise)
        for frame = 0, 1 do
            local actor = buffer.create(4 * 6 * 3)
            for z = 0, 2 do
                for y = 0, 5 do
                    for x = 0, 3 do
                        local cell = 0
                        if x == 1 or x == 2 then
                            cell = if y >= 4 then 4 else 6
                        end
                        if y == 2 + frame and (x == 0 or x == 3) then
                            cell = 4
                        end
                        if z == 0 and y == 4 and (x == 1 or x == 2) then
                            cell = 2
                        end
                        buffer.writeu8(actor, (z * 6 + y) * 4 + x, cell)
                    end
                end
            end
            actors[frame + 1] = g.voxel(4, 6, 3, palette, actor)
        end
        local view = g.look_at({ 20, 18, -25 }, { 6, 1, 6 })
        ortho = g.camera({
            view_projection = g.multiply(
                g.orthographic(-14.222222, 14.222222, -8, 8, 0.1, 100),
                view
            ),
            light = { 0.3, 0.8, -0.5 },
            ambient = 0.45,
            fog_color = BACKGROUND,
            fog_start = 0.6,
            fog_end = 1,
        })
        perspective = g.camera({
            view_projection = g.multiply(g.perspective(0.65, 16 / 9, 1, 100), view),
            light = { 0.3, 0.8, -0.5 },
            ambient = 0.45,
            fog_color = BACKGROUND,
            fog_start = 0.985,
            fog_end = 1,
        })
        pyramid = g.mesh({
            { position = { 0, 0, 0 }, color = 0xff6b72ed },
            { position = { 4, 0, 0 }, color = 0xff6b72ed },
            { position = { 4, 0, 4 }, color = 0xff6b72ed },
            { position = { 0, 0, 4 }, color = 0xff6b72ed },
            { position = { 2, 5, 2 }, color = 0xffb9ceff },
        }, { 0, 1, 4, 1, 2, 4, 2, 3, 4, 3, 0, 4, 0, 3, 2, 0, 2, 1 })
    end,
    update = function(_dt: number)
        tick += 1
        local high = byt.button("action")
        byt.display(if high then 640 else 320, if high then 360 else 180)
        if byt.button("down") then
            local cell = buffer.create(1)
            buffer.writeu8(cell, 0, (tick % 2) * 3)
            g.edit(room, 5, 3, 11, 1, 1, 1, cell)
        end
    end,
    draw = function()
        local screen = gfx.screen()
        local pass = gfx.begin_pass(screen, { clear = true, color = BACKGROUND })
        local high = byt.button("action")
        g.bind(
            pass,
            if high then depthHigh else depthLow,
            if byt.button("right") then perspective else ortho
        )
        g.draw(pass, room)
        g.draw(pass, actors[math.floor(tick / 15) % 2 + 1], g.pose(3, 1, 3, 0, 0.65))
        g.draw(pass, pyramid, g.pose(7, 1, 6, 0, 0.7))
        local angle = tick * 0.015
        g.draw(pass, prop, g.pose(7, 2, 2, angle, 0.65))
        if byt.button("up") then
            g.draw(pass, checker, g.pose(2, 2, 4, angle, 0.35))
        end
        if byt.button("left") then
            for z = 0, 7 do
                for x = 0, 7 do
                    g.draw(pass, prop, g.pose(1 + x * 1.2, 1, 1 + z * 1.2, angle, 0.2))
                end
            end
        end
        local scale = if high then 2 else 1
        gfx.transform(pass, { scale, 0, 0, scale, 0, 0 })
        gfx.rect(pass, 8, 8, 304, 19, 0xff382925)
        gfx.text(pass, "VOXEL GARDEN / SHARED 3D", 15, 14, 0xffdceeff)
        gfx.text(pass, "DOWN:EDIT UP:STRESS LEFT:64 PROPS", 12, 157, 0xffdceeff)
        gfx.text(pass, "RIGHT:PERSPECTIVE ACTION:640X360", 12, 168, 0xffdceeff)
        gfx.end_pass(pass)
        gfx.present(screen)
    end,
}

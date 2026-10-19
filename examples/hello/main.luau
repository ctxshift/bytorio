-- The same game module is loaded by the native and browser players.
local x, y = 184, 100
local elapsed = 0
local previousAction = false

return {
    init = function()
        console.sound()
    end,

    update = function(dt: number)
        elapsed += dt
        local speed = 100 * dt
        if console.button("left") then x -= speed end
        if console.button("right") then x += speed end
        if console.button("up") then y -= speed end
        if console.button("down") then y += speed end
        local pressed, px, py = console.pointer()
        if pressed then x, y = px - 8, py - 8 end
        x = math.clamp(x, 0, 368)
        y = math.clamp(y, 0, 200)

        local action = console.button("action") or pressed
        if action and not previousAction then console.sound() end
        previousAction = action
    end,

    draw = function()
        console.clear(20, 24, 40)
        console.sprite(x, y + math.sin(elapsed * 3) * 2)
    end,
}

--!strict
local console = require("@console")
local x,y = 40,40
local function init()
    x,y=40,40
    console.sound()
end
local function update(dt:number)
    if console.button("left") then x-=90*dt end
    if console.button("right") then x+=90*dt end
    if console.button("up") then y-=90*dt end
    if console.button("down") then y+=90*dt end
    local active,px,py=console.pointer()
    if active then x,y=px-8,py-8 end
    local w,h=console.size()
    x,y=math.clamp(x,0,w-16),math.clamp(y,20,h-16)
    if console.pressed("action") then console.sound() end
end
local function draw()
    console.clear(console.rgb(23,32,46))
    console.sprite(0,x,y)
    console.text("HELLO, CONSOLE!",8,7,console.rgb(244,236,214))
end
return {init=init,update=update,draw=draw}

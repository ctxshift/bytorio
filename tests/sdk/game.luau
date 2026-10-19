--!strict
local console = require("@console")
local random,edges=0,0
local px,py=0,0
local function init() random,edges=0,0;console.seed(123);console.sound() end
local function update(dt:number)
    assert(dt==1/60)
    if console.pressed("action") then edges+=1;console.sound() end
    if console.released("action") then edges+=10 end
    local active,x,y=console.pointer()
    px,py=if active then x else 0,if active then y else 0
    random=console.random_u32()%1000
    if console.ticks()==20 or console.ticks()==60 then console.display(320,180) end
    if console.ticks()==40 then console.display(640,360) end
    console.debug_position(random,edges)
end
local function draw()
    console.clear(console.rgb(23,32,46))
    console.rect(-2,-2,8,8,console.rgb(255,0,0))
    console.rect(12,12,0,20,console.rgb(0,0,0))
    console.sprite(0,-4,8,2)
    console.sprite_size(0,60,30,7+console.ticks()%25,11)
    console.text("SDK\nPARITY",20,50,console.rgb(255,255,255))
    console.rect(math.floor(px),math.floor(py),3,3,console.rgb(0,255,0))
    if console.button("right") then console.rect(40,90,8,8,console.rgb(0,0,255)) end
end
return {init=init,update=update,draw=draw}

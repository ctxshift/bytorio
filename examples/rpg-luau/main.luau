-- Mossglen: identical rules and assets to the Odin cartridge.
local g = graphics
local p = assets.palette
local s
local numbers = {}
for i = 0, 20 do numbers[i] = tostring(i) end
local tileIds = { G=0, P=1, W=2, T=3, R=4, H=5, F=10, B=11 }

local function say(message: string)
    s.mode = "dialog"
    s.message = message
    console.sound()
end
local function near(x: number, y: number): boolean
    return math.abs(s.x-x)+math.abs(s.y-y) <= 1
end
local function tile(x: number, y: number): string
    if x < 0 or x >= 32 or y < 0 or y >= 20 then return "T" end
    return string.sub(assets.world[y+1],x+1,x+1)
end
local function battle()
    local retaliation = 3
    if s.choice == 0 then
        s.enemy -= 4
        s.message = "YOU STRIKE FOR 4. SLIME HITS FOR 3."
    elseif s.choice == 1 then
        retaliation = 1
        s.message = "YOU BRACE. SLIME HITS FOR 1."
    else
        if s.potions == 0 then s.message = "NO POTIONS LEFT. CHOOSE ANOTHER ACTION."; return end
        s.potions -= 1
        s.hp = math.min(20,s.hp+8)
        s.message = "POTION RESTORES 8. SLIME HITS FOR 3."
    end
    console.sound()
    if s.enemy <= 0 then
        s.won = true
        say("THE SLIME RETREATS! THE GROVE IS SAFE.\nFIND THE GOLDEN SUNLEAF TO THE EAST.")
        return
    end
    s.hp = math.max(0,s.hp-retaliation)
    if s.hp == 0 then
        s.defeated = true
        say("YOU FALL... THE HEALER BRINGS YOU HOME.\nREST, THEN TRY THE GROVE AGAIN.")
    end
end

return {
    init = function()
        s = { x=5,y=6,hp=20,potions=1,enemy=10,choice=0,quest=false,herb=false,
            won=false,complete=false,defeated=false,mode="explore",message="",previous=0,cooldown=0,steps=0 }
        console.sound()
    end,
    update = function(_dt: number)
        local buttons = 0
        for i, name in {"left","right","up","down","action"} do
            if console.button(name) then buttons = bit32.bor(buttons,2^(i-1)) end
        end
        local pressed = bit32.band(buttons,bit32.bnot(s.previous))
        s.previous = buttons
        s.cooldown = math.max(0,s.cooldown-1)
        local action = bit32.band(pressed,16) ~= 0
        if s.mode == "dialog" then
            if action then
                s.mode = "explore"
                if s.defeated then
                    s.x,s.y,s.hp,s.potions,s.enemy = 5,6,20,1,10
                    s.defeated = false
                end
            end
            return
        end
        if s.mode == "battle" then
            if bit32.band(pressed,5) ~= 0 then s.choice = (s.choice+2)%3 end
            if bit32.band(pressed,10) ~= 0 then s.choice = (s.choice+1)%3 end
            if action then battle() end
            return
        end
        if action then
            if near(5,4) then
                if s.herb and not s.complete then
                    s.complete = true; s.hp = 20
                    say("YOU BROUGHT THE SUNLEAF! THANK YOU.\nMOSSGLEN IS SAFE. QUEST COMPLETE!")
                elseif s.complete then say("THE GROVE IS QUIET AGAIN.\nTHANK YOU, FRIEND OF MOSSGLEN.")
                else
                    s.quest = true
                    say("A SLIME GUARDS THE SUNLEAF GROVE.\nCROSS THE EAST BRIDGE. BRING ONE HOME.")
                end
            elseif near(24,6) and not s.herb then
                if not s.quest then say("A GOLDEN SUNLEAF. SOMEONE MAY NEED IT.\nSPEAK TO THE HEALER IN MOSSGLEN FIRST.")
                elseif not s.won then say("THE SLIME KEEPS YOU FROM THE SUNLEAF.\nFACE IT IN THE GROVE FIRST.")
                else s.herb = true; say("YOU FOUND THE SUNLEAF!\nRETURN TO THE HEALER IN MOSSGLEN.") end
            else say("ARROWS OR WASD TO WALK. SPACE TO TALK.\nSEEK THE HEALER BESIDE THE RED HOUSE.") end
            return
        end
        local dx,dy = 0,0
        if bit32.band(buttons,1) ~= 0 then dx = -1
        elseif bit32.band(buttons,2) ~= 0 then dx = 1
        elseif bit32.band(buttons,4) ~= 0 then dy = -1
        elseif bit32.band(buttons,8) ~= 0 then dy = 1 end
        if dx == 0 and dy == 0 then s.cooldown = 0; return end
        if s.cooldown > 0 then return end
        s.cooldown = 8
        local nx,ny = s.x+dx,s.y+dy
        local t = tile(nx,ny)
        if t == "W" or t == "T" or t == "R" or t == "H" or (nx == 5 and ny == 4) then return end
        s.x,s.y = nx,ny
        s.steps += 1
        if nx == 19 and ny == 6 and not s.won then
            s.mode,s.enemy,s.choice = "battle",10,0
            s.message = "A MOSS SLIME BLOCKS THE GROVE!"
            console.sound()
        end
    end,
    draw = function()
        console.clear(21,32,50)
        local cx = math.clamp(s.x-11,0,8)*16
        local cy = math.clamp(s.y-4,0,10)*16
        for y = 0,19 do
            for x = 0,31 do
                local sx,sy = x*16-cx,24+y*16-cy
                if sx >= 0 and sx < 384 and sy >= 24 and sy < 184 then g.sprite(tileIds[tile(x,y)],sx,sy) end
            end
        end
        local function actor(id: number,x: number,y: number)
            local sx,sy = x*16-cx,24+y*16-cy
            if sx >= 0 and sx < 384 and sy >= 24 and sy < 184 then g.sprite(id,sx,sy) end
        end
        actor(7,5,4)
        if not s.won then actor(9,19,6) end
        if not s.herb then actor(8,24,6) end
        actor(if s.steps%2 == 0 then 6 else 12,s.x,s.y)
        g.rect(0,0,384,24,p[1]); g.rect(0,22,384,2,p[3])
        g.text("MOSSGLEN",8,8,p[15])
        g.text("HP",206,8,p[13]); g.text(numbers[s.hp],224,8,p[16]); g.text("/20",236,8,p[15])
        g.text("POTION",276,8,p[14]); g.text(numbers[s.potions],324,8,p[16])
        g.rect(0,184,384,32,p[1]); g.rect(0,184,384,2,p[3])
        local objective = "TALK TO THE HEALER BY THE RED HOUSE"
        if s.complete then objective = "QUEST COMPLETE - THANK YOU FOR PLAYING"
        elseif s.herb then objective = "SUNLEAF FOUND - RETURN TO THE HEALER"
        elseif s.quest then objective = "CROSS THE EAST BRIDGE - FIND SUNLEAF" end
        g.text(objective,8,191,p[15]); g.text("ARROWS: WALK   SPACE: TALK / CONFIRM",8,203,p[10])
        if s.mode == "dialog" then
            g.rect(8,135,368,46,p[2]); g.rect(10,137,364,42,p[1])
            g.text(s.message,18,144,p[16]); g.text("SPACE >",312,166,p[14])
        elseif s.mode == "battle" then
            g.rect(0,24,384,160,p[1]); g.rect(0,96,384,88,p[3]); g.rect(0,96,384,3,p[4])
            g.sprite(6,58,66,3); g.sprite(9,261,55,4)
            g.text("TRAVELER",48,35,p[15]); g.text("MOSS SLIME",252,35,p[15])
            g.text("HP",264,124,p[16]); g.text(numbers[math.max(0,s.enemy)],284,124,p[16])
            g.rect(8,141,368,38,p[2]); g.text(s.message,16,149,p[16]); g.text("CHOOSE WITH ARROWS. SPACE TO CONFIRM.",16,164,p[14])
            g.rect(0,184,384,32,p[1])
            for i, label in {"ATTACK","GUARD","POTION"} do
                local x = 12+(i-1)*124
                if s.choice == i-1 then g.rect(x,188,112,22,p[4]) end
                g.text(label,x+14,195,p[16])
            end
        end
    end,
}

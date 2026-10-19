--!strict
-- Editor declarations. The bundler replaces this module with the executor bridge.
local function unavailable(): never error("The console native bridge is provided by the player") end
return {
    display=function(_w:number,_h:number) unavailable() end,
    clear=function(_r:number,_g:number,_b:number) unavailable() end,
    rect=function(_x:number,_y:number,_w:number,_h:number,_color:number) unavailable() end,
    draw_sprite=function(_id:number,_x:number,_y:number,_scale:number) unavailable() end,
    draw_sprite_size=function(_id:number,_x:number,_y:number,_w:number,_h:number) unavailable() end,
    draw_text=function(_text:string,_x:number,_y:number,_color:number) unavailable() end,
    graphics_assets=function(_data:string) unavailable() end,
    buttons=function():number return unavailable() end,
    pointer=function():(boolean,number,number) unavailable();return false,0,0 end,
    sound=function() unavailable() end,
    debug_position=function(_x:number,_y:number) unavailable() end,
}

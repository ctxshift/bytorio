package main
import "base:runtime"
import abi "../../runtime/odin/abi"
import g "../../runtime/odin/graphics"
import "assets"
frame: abi.Frame
frame_ticks: u32
@(export) game_abi :: proc "c" () -> u32 {return abi.VERSION}
@(export) game_frame_size :: proc "c" () -> u32 {return abi.FRAME_BYTES}
@(export) game_display_mode :: proc "c" () -> u32 {return g.display_mode}
@(export) game_init :: proc "c" () {context=runtime.default_context();_=g.set_display(abi.DISPLAY_LOW);frame_ticks=0;init()}
@(export) game_update :: proc "c" (buttons,pointer:u32,x,y:f64) {context=runtime.default_context();frame_ticks+=1;update(buttons)}
@(export) game_draw :: proc "c" () -> u32 {
    context=runtime.default_context();g.begin();draw()
    frame=abi.Frame{version=abi.VERSION,clear=0xff241919,sprite_x=-4096,sprite_y=-4096,ticks=frame_ticks,sounds=s.sounds,x=f64(s.x),y=f64(s.speed)}
    return u32(uintptr(&frame))
}
@(export) game_commands :: proc "c" () -> u32 {return u32(uintptr(&g.commands))}
@(export) game_command_count :: proc "c" () -> u32 {return 0xffffffff if g.overflow else g.count}
@(export) game_command_stride :: proc "c" () -> u32 {return 32}
@(export) game_text :: proc "c" () -> u32 {return u32(uintptr(&g.text_bytes))}
@(export) game_text_size :: proc "c" () -> u32 {return g.text_count}
@(export) game_assets :: proc "c" () -> u32 {return u32(uintptr(&assets.raster))}
@(export) game_assets_size :: proc "c" () -> u32 {return u32(size_of(assets.raster))}
inspection: [10]i32
@(export) game_inspect :: proc "c" () -> u32 {
    inspection={i32(s.distance),i32(s.x),i32(s.speed),i32(s.charge),i32(s.elapsed),i32(s.hits),i32(s.offroad),i32(s.boosts),i32(s.finished),i32(s.ticks)}
    return u32(uintptr(&inspection))
}

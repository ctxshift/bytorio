# SDK API 0.1.0

This page documents implemented calls. The proposed next interface is described
in [typed graphics and audio resources](../docs/resource-av-spec.md), including
equivalent Luau/Odin operation shapes. Those resource calls are not available yet.

Luau imports `local console = require("@console")`. Odin imports
`console "sdk:console"`. Sprite IDs start at zero. Drawing coordinates use the
current display. Colors are opaque packed u32 values, made with `rgb`.

| Operation | Luau | Odin |
| --- | --- | --- |
| Select display | `console.display(320,180)` or `(640,360)` | `console.display(.Low)` or `(.High)` |
| Active dimensions | `local w,h=console.size()` | `w,h:=console.size()` |
| Construct color | `console.rgb(r,g,b)` | `console.rgb(r,g,b)` |
| Set persistent clear color | `console.clear(color)` | `console.clear(color)` |
| Rectangle | `console.rect(x,y,w,h,color)` | `console.rect(x,y,w,h,color)` |
| Sprite, scale defaults to 1 | `console.sprite(id,x,y,scale)` | `console.sprite(id,x,y,scale)` |
| Sprite at pixel size | `console.sprite_size(id,x,y,w,h)` | `console.sprite_size(id,x,y,w,h)` |
| ASCII text | `console.text(value,x,y,color)` | `console.text(value,x,y,color)` |
| Held button | `console.button("left")` | `console.button(.Left)` |
| Press/release edge | `console.pressed("action")`, `released` | `console.pressed(.Action)`, `released` |
| Raw held mask | `console.buttons()` | `console.buttons()` |
| Pointer snapshot | `local active,x,y=console.pointer()` | `active,x,y:=console.pointer()` |
| Current tick | `console.ticks()` | `console.ticks()` |
| Request sound cue | `console.sound()` | `console.sound()` |
| Set deterministic seed | `console.seed(value)` | `console.seed(value)` |
| Next random u32 | `console.random_u32()` | `console.random_u32()` |
| Development position | `console.debug_position(x,y)` | `console.debug_position(x,y)` |

Buttons are left/right/up/down/action in Luau, `.Left/.Right/.Up/.Down/.Action`
in Odin. `pressed` and `released` are stable throughout a tick and its draws;
querying them does not consume an event. Inactive pointers return false,0,0.
`debug_position` is an optional pair of numbers for replay tools, bounded to ±4096;
it does not move sprites or alter simulation. The version strings are Luau's
`console.version` and Odin's `console.VERSION`.

The build tool supplies the immutable atlas. Advanced Lua bundlers can call
`console.assets(base64Packet)` only during module loading or initialization.
Odin entry generators pass a stable `[]u8` packet to `console.start`; that memory
must remain valid throughout cartridge execution. The `_wrap` Luau function and
Odin lifecycle exports are SDK integration details, not game callbacks.

Rectangles accept dimensions 0..4096. Sprite integer scales are 1..8; sized sprites
are 1..128 pixels wide/high. Positions are ±4096; each text command is at most
1024 ASCII bytes. Luau fractional drawing coordinates truncate toward zero.
Both SDKs stop the cartridge on invalid arguments or frame-capacity exhaustion.
All limits, packet layouts, ordering and restart rules are defined in the
[cartridge specification](../docs/cartridge-spec.md).

This release has no custom sample playback, mixer voices, music, saves, network,
mesh API or general filesystem access. Those require future versioned features;
there are no placeholder calls that silently succeed.

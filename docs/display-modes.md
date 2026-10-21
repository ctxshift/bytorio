# Display modes

The console supports exactly two square-pixel, 16:9 display modes:

| Mode | Resolution | Framebuffer bytes (RGBA8) |
| --- | --- | --- |
| Default | 640×360 | 921,600 |
| Low resolution | 320×180 | 230,400 |

Drawing coordinates, clipping and pointer coordinates use the active resolution.
All graphics, including text, render at that resolution. The player preserves
the aspect ratio and uses nearest-neighbor integer enlargement with borders.
The browser can shrink the canvas when the available viewport is smaller than
the game. Browser zoom and device pixel density are included in scale selection.
Native fullscreen is F11; the browser player has a Fullscreen button.

## Cartridge interface

Luau SDK games call `byt.display(320, 180)` or `byt.display(640, 360)`.
The initial mode is 640×360. A request is applied when the next frame is submitted.
Call it during initialization or before drawing a frame in the new mode.

Odin SDK games call `byt.display(.Low)` or `byt.display(.High)`.
The generated entry point supplies `game_display_mode`; authors do not write
this export. Both SDKs keep command clipping and host rendering in sync.
Other Odin/Wasm cartridges may export `game_display_mode() -> u32`, returning
`abi.DISPLAY_HIGH` or `abi.DISPLAY_LOW`. Width occupies the high 16 bits and
height the low 16 bits. The player queries it after `game_draw`, before rendering.
An omitted export selects 640×360. Other values stop the cartridge with an error.
The existing 40-byte frame record and ABI version remain unchanged.

The renderer reserves space for the maximum framebuffer. Active pixels are packed
with a stride of active width × 4; hashes and browser transfers cover only those
pixels. Mode switches do not reset game state or reload assets. Input sampled
before a switch uses the previously presented mode, then subsequent input uses
the new mode. Games should avoid consuming pointer input on the transition frame.

The earlier 384×216 display is retired. Historical screenshots and benchmark
results describe that older prototype; older cartridges without a mode export
now receive the default canvas. Their artwork/layout may need migration.

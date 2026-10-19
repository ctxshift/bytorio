# Copper Circuit

A small original kart-racing demo, independently written in Luau and Odin.
Both cartridges run at **320×180** through the same Odin player on native
Windows and in the browser. The console's other supported mode is 640×360;
see [display modes](display-modes.md).

The demo includes a countdown, steering, acceleration and braking, winding road,
six AI karts, collisions, off-road slowdown, a rechargeable boost, position display,
track progress, lap timing, a three-lap finish and restart. Original sprite artwork
and the existing bitmap font are packed into one shared atlas by the build tool.

## Build and play

From the repository root, with the [Odin toolchain prerequisites](odin-development.md):

```powershell
npm run build:racing
npm run serve:racing
```

Open `http://127.0.0.1:8080/comparison.html`, choose a cartridge, and press
**Start game** to unlock sound. Arrows/WASD steer, accelerate and brake;
Space boosts. Release Space after finishing and press it again to restart.
The browser includes touch controls and a Fullscreen button. Native fullscreen
is F11. Native builds are standalone applications without a webview.

```powershell
./build/racing-player/native/player.exe
./build/racing-player/native/player.exe --game build/racing-player/native/luau-executor.wasm --source build/racing-player/native/racing.luau
```

Sources:

- [Odin gameplay](../examples/racing-odin/main.odin) and [cartridge interface](../examples/racing-odin/cartridge.odin).
- [Luau gameplay](../examples/racing-luau/main.luau).
- [Shared artwork generator](../tools/build-racing-assets.mjs).
- [Browser launcher](../examples/racing-shared/launcher.html).

Both games use fixed 60 Hz simulation and integer arithmetic for state and
projection. Odin explicitly uses floor division where Luau's floating-point
division is rounded down, and wraps negative track coordinates consistently.
Gameplay is implemented separately; the build does not translate either language
into the other. The original RPG remains a separate earlier example.

## Rendering

This is a pseudo-3D road made from horizontal spans and depth-scaled sprite
billboards. It exercises simulation, command generation, text, clipping and sprite
resampling. It does not exercise textured triangle meshes, depth buffers, hills,
or a general 3D camera. Its performance cannot establish the budget for a full
DS-style 3D engine. Sound uses the player's existing cue for countdown, collision
and lap events; engine synthesis and music remain future work.

The batch renderer now accepts command kind 3 for a nearest-neighbor sprite sized
to any width/height from 1 to 128 pixels. The sprite ID occupies the command's
`color` field; `x/y/w/h` specify the destination rectangle. Source sprites remain
16×16 with transparent pixels. Odin calls `g.sprite_size(id,x,y,w,h)`; Luau calls
`console.draw_sprite_size(id,x,y,w,h)`. This allows distant karts to shrink below
16 pixels instead of jumping between whole-number enlargement steps.

## Verification and measurements

```powershell
npm run test:racing
npm run bench:racing
```

Verification compares **1,606 race/restart frames and 630 handling frames** per
cartridge, including framebuffer hashes and sound-event counts, across Node,
native Wasmtime and browser Workers. Behavioral assertions cover three completed
laps, boost exceeding normal speed, collisions, off-road driving, braking to a
stop and restart. Native SDL rendering/audio and browser keyboard/audio are
checked separately. These are deterministic scripted checks, not human playtests.

The benchmark runs a 720-frame replay, with two warmup and five measured passes
per sample, and three serial samples per variant. It reports update, command
submission, shared rasterization, browser pixel-copy cost, startup and memory.
Frame times exclude hashes, window presentation, audio and browser canvas painting;
the browser pixel copy is reported separately. Startup ends at the first rendered
frame before opening a native window. Results are in the [benchmark report](../experiments/racing/RESULTS.md).

For display regression checks, build the RPG runtime and executor first, then run:

```powershell
./tools/build-odin.ps1 -Game rpg
npm run test:display
```

That suite checks both resolutions, frame-boundary switches, bounded transfers,
SDL texture recreation, fullscreen integer scaling and invalid mode rejection.
Artifacts, replays, screenshots and complete measurement logs are under ignored
`build/racing-player/`. Distribution currently stages loose Wasm/Luau files;
the planned PNG cartridge packaging is not part of this demo.

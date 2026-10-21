# Sunline Sprint

An original eight-kart, three-lap perspective racer, implemented separately in
Luau and Odin. It is the true 3D successor to the [earlier span-rendered
demo](racing-demo.md). The course, hills, wheels, drivers and scenery use actual
depth-tested triangle meshes. The supplied grassland concept guides the red
kart, purple-haired driver, bright palette and single-screen HUD.

## Build and play

Use the pinned tools described in [development](development.md):

```text
mise run //examples/kart3d:build
mise run //examples/kart3d:serve
```

Open `http://127.0.0.1:8082/` and choose either SDK. CPU rendering is the default;
the separate GPU links explicitly request GPU rendering and resident meshes.
Press **Start game** to enable input and sound. The browser performance panel
sits below the game so it does not obscure the HUD.

Standalone native players use the same PNG cartridges:

```text
examples/kart3d/build/odin/build/native/player.exe
examples/kart3d/build/luau/build/native/player.exe
examples/kart3d/build/odin/build/native/player.exe --renderer gpu --gpu-meshes
examples/kart3d/build/luau/build/native/player.exe --renderer gpu --gpu-meshes
```

| Control | Action |
| --- | --- |
| W / Up | Accelerate; timing the press near the end of the countdown gives a launch boost |
| S / Down | Brake |
| A D / Left Right | Steer |
| Space while turning | Hop into a drift; alternate steering to charge sparks, then release Space for a mini-turbo |
| E | Spend the collected turbo item |
| Q | Toggle 320×180 / 640×360 |
| Hold Space, press Q | Cycle Auto LOD → Low detail → High detail |
| R | Restart the race |

Simulation runs at 60 Hz independently of presentation frame-rate settings.
The HUD shows time, lap, position, stored item, speed, drift charge and a minimap
with all eight racers. Grass slows the kart; the outer course boundary bounces
it back. Contact with another racer reduces speed. Ordered quarter-lap
checkpoints determine three-lap completion. Pickups supply one stored turbo.
Countdown, contact, boost and lap events use the existing sound cue.

## Implementation and limits

- [Odin game](../examples/kart3d/odin/main.odin),
  [simulation](../examples/kart3d/odin/race/race.odin) and
  [scene](../examples/kart3d/odin/scene.odin).
- [Luau game](../examples/kart3d/luau/main.luau),
  [simulation](../examples/kart3d/luau/race.luau) and
  [scene](../examples/kart3d/luau/scene.luau).
- [Course generator](../examples/kart3d/tools/course.mjs) emits the same closed, elevated
  course for both games. `mise run //examples/kart3d:generate` regenerates checked data.
- [Reference research](kart-racing-reference-research.md) separates documented
  controls and feedback from original tuning choices.

Static meshes are created once. Frames update the camera and kart transforms,
draw nearby road chunks and cull distant opponents. Both paths use the same
camera, fog, meshes and HUD; GPU residency is optional. Original glTF kart and
tree assets use the [model importer](model-import.md). The red kart, sculpted
purple hair and cape follow the supplied grassland mockup. Wheels roll around
their imported pivots, front wheels steer, and the rigid cape moves independently.
Eight paint variants share the same geometry. Textured asphalt, cutout flowers,
soft ground shadows, fading dust and additive boost trails use ordinary typed
resources. Dedicated engine audio/music and skeletal characters remain future work.

The matching low/high karts contain 314/600 triangles. Auto LOD selects high
detail within 22 world units and low beyond 26, retaining its choice between
those thresholds. Simulation updates make LOD decisions independently of render
cadence. The HUD identifies the selected detail policy. Both CPU and GPU can use
either model; lower powered devices can select Low detail. There is no additional
4,096-triangle game cap. The experimental profile's 65,536 submitted triangles
per commit and separate memory/pixel-work ceilings remain safety limits, not a
visual target or a frame-rate guarantee.

The 48-slot particle pool expires particles after 30 simulation ticks, reuses
geometry/textures/materials, sorts far-to-near and clears on restart. Resources
are created once. GPU acceleration and residency remain opt-in. See the
[effects contract](3d-effects.md) for blending and depth behavior.

Edit [the original assets](../examples/kart3d/assets/README.md), then run
`mise run //examples/kart3d:generate` to regenerate original asset files, the course
and checked SDK imports. Builds check imports against source assets. The original
asset generator owns its glTF files; adopt edited glTF inputs deliberately if
switching authoring to a modeling tool. No external model decoder runs in games.

Handling is a road-relative arcade simulation: karts follow interpolated course
height with an animated hop. It is not a rigid-body suspension model, free
off-track driving or reverse driving. Opponents follow fixed lanes at different
speeds. The launch and alternating-steering drift mechanics are implemented,
but matching a commercial racer's feel requires further hands-on tuning.

## Validation and measurements

```text
mise run validate test:kart3d
mise run validate test:kart3d:gpu
mise run //examples/kart3d:benchmark
```

Pure simulation tests assert independent expected results for countdown,
launch timing, steering charge/release, off-road limits, collisions, ordered
checkpoints, inventory and restart. A scripted driver completes three laps,
then exercises both display modes, drift, off-road motion, braking and restart.
Internal state is compared between SDKs; CPU images match across SDKs and
native/browser hosts. GPU images match between SDKs on each host. Cross-host
GPU captures permit bounded edge/raster rounding differences: at most 0.1% of
pixels differ by more than two channel levels, with RGB RMS at most two levels.
Raw captures and replay inputs are retained under `examples/kart3d/build/validation/`.

The benchmark retains raw native/browser data under `examples/kart3d/build/benchmarks/`.
It runs two warm-up and five measured 300-frame race starts, excluding the first
180 countdown frames from frame summaries: 600 moving samples per case at
320×180, SSAA off. GPU cases explicitly enable resident meshes. Measurements
include rendering completion, exclude diagnostic hashing, audio, main-thread
delivery and display scanout, and retain normal OS/executor caches. Native
startup ends at initialization; browser startup includes its first frame.
This short rollout does not establish worst-case full-course performance or a
minimum-device 60 FPS guarantee.

### Earlier baseline rollout observation

These historical measurements precede imported assets/effects and do not measure
the polished version. Measured on 2026-10-21, Windows native and Chrome browser, with both PNGs loaded
locally. Times below are pipeline p95 milliseconds; each case has 600 moving
samples. This run had no samples over 16.67 ms.

| SDK | PNG bytes | Native CPU | Browser CPU | Native GPU | Browser GPU |
| --- | ---: | ---: | ---: | ---: | ---: |
| Odin | 215,586 | 4.74 | 5.00 | 2.05 | 1.70 |
| Luau | 133,604 | 5.38 | 5.30 | 3.46 | 2.50 |

Observed startup was 63 / 36 ms on native CPU and 35 / 99 ms in the browser for
Odin / Luau respectively. GPU initialization raised native startup to about
354 / 345 ms; browser startup was 75 / 86 ms. These are single observations
with normal caches, not cold-download latency distributions.

Guest Wasm memory settled at 3.19 MiB for Odin and 5.00 MiB for Luau; the Luau
heap is included in its guest memory. Browser runtime Wasm memory was 18.19 MiB
on CPU and 28.94 MiB with GPU enabled. Live logical resources were 1.67 MiB and
overlap runtime memory. Native working sets were about 26 / 22 MiB on CPU and
102 / 98 MiB on GPU. The resident GPU mesh cache held 2.45 MiB. These figures
describe different overlapping allocations and must not be added together.

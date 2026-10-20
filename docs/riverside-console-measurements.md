# Riverside console GPU qualification

The preserved riverside scene has matching Odin and Luau cartridges running
through the standalone and browser players. This workload qualifies the actual
console backend separately from the independent WebGL viewer.

## Reproduce

From the repository root:

```text
mise run build:riverside
mise run bench:riverside
```

The hardware benchmark requires native OpenGL and installed Chrome with WebGL2;
`PLAYER_BROWSER_CHANNEL` selects another installed browser channel. Builds finish
before timing starts. Do not overlap measurement with heavy builds or tests.
Other desktop GPU activity remains uncontrolled.

Serve `build/compact-3d` with the existing development server. Open
`/riverside/odin/build/web/player.html?renderer=gpu&gpu-meshes&ssaa=1080p&smooth-pan` or
the matching `/riverside/luau/` path. Both exports include PNG cartridges.
For native:

```text
build/compact-3d/riverside/odin/build/native/player.exe --renderer gpu --gpu-meshes --ssaa 1080p --smooth-pan
build/compact-3d/riverside/odin/build/native/player.exe --renderer cpu --ssaa 2x --smooth-pan
```

WASD walks the rabbit, Q/E rotates the camera, arrows pan, and R resets position
and camera. Space selects 640×360 while held; the default is 320×180. Movement
uses the viewer's baked terrain/obstacle map. These independent controls use the
optional extended input bits; legacy-only benchmark masks retain the original
repeatable pan/orbit trajectories for comparison with the baseline.
The source templates are `experiments/voxel-resolution/console-game.odin` and
`console-game.luau`; use the task to embed their generated scene data. These are
renderer qualification cartridges with basic walking and collision.

CPU is still the default. Supersampling, orthographic snapping and smooth pan
work on CPU and GPU; only resident meshes require GPU selection. In the browser,
use the graphics settings and apply them to restart. A direct CPU comparison is
`player.html?renderer=cpu&ssaa=1080p&smooth-pan`. Full-scene CPU supersampling is
functional, but is not qualified for 60 fps. The live overlays report delivered
FPS, uploads and separately labeled memory domains.

## Surface preservation and limits

The source has 1,023,096 world and 8,052 rabbit vertices: 343,716 triangles.
Direct submission exceeds the current 65,536-triangle commit limit. The builder
merges adjacent unit faces only when plane, winding and baked color agree. It
checks face coverage, rejects duplicates and keeps rabbit geometry separate.
The result is 16,367 world quads and 536 rabbit quads: 33,806 triangles, with the
same opaque surface field and baked shading. It does not drop objects, crop
the visible scene, reduce voxel density or change published profile limits.
Tessellation changes, so raster rounding need not be bit-identical to the viewer.

Both languages upload 512-face mesh chunks over 33 updates. This keeps upload
packets bounded and temporary Luau vertex tables inside its existing 4 MiB heap.
Luau reuses vertex records rather than continually allocating nested tables.
Odin embeds a binary field at compile time. Luau embeds a bounded LZ fixture
stream and incrementally decodes it over 18 updates to preserve the native
instruction budget. Odin mirrors that loading schedule for exact replay parity.
The fixture includes the bounded walk map; decoding and uploads take 51 updates.
Unchanged camera resources are reused instead of recreated every draw.
This is an experiment-local encoding, not a new cartridge or asset protocol.
The PNG container, resource API and player limits are unchanged.

## Method and correctness

`build/compact-3d/riverside/performance.json` retains device/browser identity,
source and binary hashes, geometry, startup, memory and stage statistics.
Per-case raw JSON and 1080p presentation captures sit beside it.

Each case uses two warm-up passes and five measured passes. Each pass contains
88 updates; the first 58 are excluded from steady-state statistics, covering
decoding, all uploads and seven full-scene warm-up updates. The remaining 30
give 150 samples per SDK/host/motion/resolution. Native retains Wasmtime fuel
metering. Both hosts load PNGs and use resident GPU meshes, 1080p SSAA, camera snapping and
smooth presentation. Cases cover pan and orbit at both outputs with rabbit motion.

Cross-SDK logical hashes must match exactly on each host. Native OpenGL and
browser ANGLE can differ at coverage/rounding ties with resident f32 transforms.
For each cross-host hash mismatch, a separate untimed replay captures both raw
logical RGBA images. The comparator permits at most 0.1% changed pixels, RMS
8-bit channel delta 0.5, and linear channel/alpha delta of one supersample's
coverage plus 2/255. The actual maximum was two changed pixels per frame.
This is bounded cross-driver agreement, not bit-exact native/browser rendering.
CPU/reference comparisons retain their exact checks.

The verifier also checks expected triangle counts, verifies active 1920×1080
smooth presentation and rejects unexpectedly empty captures. Independent unit
fixtures check merging, signed coordinates, palette values, winding, duplicates
and compression overlap/window boundaries. Parity complements these independent
checks; it is not itself a visual reference.

Timing includes updates, resource transport/validation, draw commit, CPU work
accounting, GPU submission/synchronization/readbacks, CPU logical composition and
GPU smooth presentation. GPU completion is synchronized. Browser presentation
transfers an ImageBitmap; the enlarged CPU frame-buffer copy is eliminated.
Draw-commit timing includes rendering, not just command submission. Stage
percentiles must not be added to produce a total percentile.

Window presentation, Worker message delivery, canvas/compositor, scanout, audio
and a full gameplay simulation are excluded. Startup ends at the initial loading
frame before scene uploads finish; it is not time to a fully visible scene.
Resource work counters cover the final replay pass, including loading, while
steady-state timings exclude those frames. Process working set, guest/runtime
linear memory and resource budget bytes are different accounting domains.

## Resident mesh and GPU presentation results

Measured on 2026-10-20 on Windows x64 with an i7-11700K and RTX 3090, using
Chrome 155.0.8059.41 for the browser. The report enumerates browser GPU devices;
it does not separately record the native OpenGL adapter string. All eight cases
passed exact same-host cross-SDK comparisons and bounded cross-driver image
comparisons. Active smooth presentation and expected geometry counts passed.
All 2,400 steady-state samples stayed below 16.67 ms; both recorded
`performance60Hz` checks passed. This qualifies the measured pipeline on this
machine, not physical scanout or low-powered/integrated/mobile hardware.

Observed total p95 milliseconds:

| SDK  | Output  | Motion | Native | Browser |
| ---- | ------- | ------ | -----: | ------: |
| Odin | 320×180 | Pan    |   3.54 |    5.00 |
| Odin | 320×180 | Orbit  |   3.71 |    4.50 |
| Odin | 640×360 | Pan    |   6.66 |    7.50 |
| Odin | 640×360 | Orbit  |   5.42 |    7.80 |
| Luau | 320×180 | Pan    |   3.55 |    5.50 |
| Luau | 320×180 | Orbit  |   3.86 |    5.50 |
| Luau | 640×360 | Pan    |   6.48 |    8.30 |
| Luau | 640×360 | Orbit  |   5.45 |    8.20 |

Each scene loads 33 resident meshes once. Across seven benchmark passes, exactly
231 uploads and 8,547 cache hits were recorded, with no steady-state geometry
uploads. One scene's expanded geometry is 4.64 MiB. Replays allocate new monotonic
geometry versions, so the cache retained 32.50 MiB across the seven passes; it is
bounded independently to 64 MiB/1,024 entries. Browser explicit texture estimates
were 25.53 MiB at 320×180 and 29.45 MiB at 640×360, excluding driver overhead.
Logical attachment/presentation uploads remain: resident geometry does not mean
zero upload traffic. These counters are visible during interactive play.

The main removed costs were repeated CPU clipping/staging and enlarged CPU
presentation. Checked word decoding, overwritten scratch allocation, trivial
clipping acceptance/rejection and discardable attachment clears also reduce work.
CPU position transforms and bounds still enforce the original logical resource
work limits. GPU rasterization still synchronously reads logical color/depth for
transactional CPU composition. The independent viewer's approximately 2 ms GPU
timings exclude console work and remain a different measurement.

Observed guest linear memory was 3.50 MiB for Odin and 6.44 MiB for Luau; Luau
heap peak was 3.62 MiB, within the unchanged 4 MiB ceiling. Browser runtime linear
memory reached 27.88 MiB at the low output and 34.06 MiB at the high output.
Native resource-budget peaks were 6.52/9.15 MiB; browser peaks were 6.27/8.90 MiB.
Native process working set was approximately 142–156 MiB after repeated loads.
These domains overlap or describe different processes;
do not sum them into a single memory requirement.

The explicit f32 view-matrix rounding in the Luau cartridge is intentional.
Odin's typed matrix rounds its elements before multiplication; retaining Luau
double precision until afterward changed edge pixels during orbit. Matching
the input precision restored exact traces without weakening comparison tolerances.

## Historical streamed baseline and next gate

The earlier same-day streamed pipeline measured native p95 43.56–46.51 ms and
browser p95 70.60–74.10 ms. All 2,400 samples exceeded the 60 Hz budget. Its CPU
presenter built the 1080p image and copied it to the browser; triangles were
transformed/clipped/staged on CPU every frame. The retained local baseline is
`build/compact-3d/riverside/performance-streamed-baseline.json`. See the
[pipeline analysis](riverside-pipeline-analysis.md) for the evidence behind the
optimization; the new results measure the combined changes rather than isolating
each optimization's contribution.

Keep color/depth resident across compatible passes next, synchronizing for actual
CPU consumers while preserving rollback, depth, resource bounds and HUD
composition. The CPU reference and optional CPU quality path remain available.
Qualify integrated/mobile devices separately before setting a minimum GPU target.

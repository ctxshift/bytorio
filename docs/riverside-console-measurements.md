# Riverside console GPU qualification

The preserved riverside scene has matching Odin and Luau cartridges running
through the standalone and browser players. This workload qualifies the actual
console backend separately from the independent WebGL viewer.

## Reproduce

From the repository root:

```text
mise run build:riverside
mise run bench:riverside
mise run bench:riverside:startup
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

For the experimental **Whole-scene surface samples** comparison, use
`/riverside/odin/build/web/player.html?renderer=gpu&surface-samples&ssaa=1080p&smooth-pan`
or select the checkbox in graphics settings and apply. Native:

```text
build/compact-3d/riverside/odin/build/native/player.exe --renderer gpu --surface-samples --ssaa 1080p --smooth-pan
mise run validate test:riverside:surface
```

The same option also works with the Luau cartridge. Existing triangle, CPU and
GPU quality modes remain available. The full scene has 687,432 fixed sample
identities at 0.5-unit spacing, represented by 171,858 resident patches using
8,249,184 bytes (7.87 MiB). These figures exclude textures, source meshes, temporary
generation storage and driver overhead. See the [mode's limits](compact-3d.md#experimental-whole-scene-surface-samples).
The GPU verification covers both display sizes, SSAA off/2×/1080p, walking,
rotation, pan and cache reuse; its local report is `surface-report.json` beside
the generated cartridges. Existing timing results below describe triangle modes,
not this experiment.

CPU is still the default. Supersampling, orthographic snapping and smooth pan
work on CPU and GPU; resident meshes and surface samples require GPU selection. In the browser,
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

Refreshed at revision `34f17b0` on 2026-10-20 on Windows x64 with an i7-11700K and RTX 3090, using
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
| Odin | 320×180 | Pan    |   3.75 |    4.70 |
| Odin | 320×180 | Orbit  |   3.40 |    4.20 |
| Odin | 640×360 | Pan    |   6.20 |    7.90 |
| Odin | 640×360 | Orbit  |   5.24 |    6.60 |
| Luau | 320×180 | Pan    |   4.02 |    4.90 |
| Luau | 320×180 | Orbit  |   3.62 |    6.00 |
| Luau | 640×360 | Pan    |   5.24 |    8.40 |
| Luau | 640×360 | Orbit  |   5.26 |    8.80 |

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
Native resource-budget peaks were 6.51/9.15 MiB; browser peaks were 6.26/8.90 MiB.
Native process working set was approximately 141–148 MiB after repeated loads.
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

## CPU smooth-pan regression and interactive measurements

With supersampling off, the initial CPU smooth presenter reduced a static
320×180 view from about 60 FPS to 13 FPS. Snapping alone, and smooth presentation
at a 1:1 display size, both retained 60 FPS. The expensive operation was enlarged
CPU presentation: floating-point source-coordinate calculations and composition
ran for every presentation pixel. The replacement partitions at the shifted
world and unshifted HUD grid boundaries, shades constant rectangles once and
copies repeated rows. An independent full-image reference verifies both output
modes, positive/negative residuals, translucent edges and HUD boundaries.

There were two additional scheduling costs. Catch-up performed up to five full
draws before delivering one image; it now performs all fixed updates and draws
once. This follows the existing side-effect-free draw contract. A five-tick
Worker regression check verifies five simulation ticks with one frame's upload
traffic. Browser scheduling also resumes work after a response or tick deadline,
instead of waiting for another monitor refresh before dispatching to the Worker.
Native catch-up uses the same update-then-draw ordering. Replay benchmarks retain
one draw per recorded tick, so their deterministic traces do not change.

`mise run bench:riverside:cpu` measures actual browser frame delivery through the
player UI, with 1920×1080 presentation and two seconds of observation per case.
Loading plus 12 updates precede measurement. It records runtime/script/cartridge
hashes, FPS, render p50/p95 and memory in
`build/compact-3d/riverside/cpu-performance.json`. These short interactive samples
include frame transport and main-thread scheduling; they are a different metric
from the synchronized render benchmark above. Desktop activity and physical
scanout remain uncontrolled. The resident GPU replay benchmark above measures one
draw per recorded tick and bypasses the CPU presenter and interactive scheduler.

Observed browser FPS after the fixes, on the same qualification machine:

| Output  | CPU settings             | Motion | Odin | Luau |
| ------- | ------------------------ | ------ | ---: | ---: |
| 320×180 | SSAA off                 | Static | 59.8 | 60.0 |
| 320×180 | SSAA off, snap           | Static | 60.0 | 59.8 |
| 320×180 | SSAA off, snap, smooth   | Static | 60.1 | 59.7 |
| 320×180 | SSAA off, snap, smooth   | Orbit  | 59.0 | 59.2 |
| 320×180 | SSAA off, snap, smooth   | Walk   | 59.8 | 59.1 |
| 640×360 | SSAA off, snap, smooth   | Static | 37.4 | 37.2 |
| 320×180 | 2× SSAA, snap, smooth    | Static | 43.8 | 43.8 |
| 320×180 | 1080p SSAA, snap, smooth | Static | 10.0 |  9.9 |

The independent JavaScript viewer performs supersampling in WebGL shaders; it
has no matching CPU supersampling mode. Its high frame rate is a GPU result.
The console GPU path also meets the 60 Hz render budget on this machine.
The software rasterizer has substantial optimization work remaining at higher
sample/output sizes; the CPU results above do not qualify 1080p software SSAA
for 60 FPS. The console currently advances simulation at a fixed 60 Hz.

## Cartridge size and startup

The startup snapshot below uses the same hardware and revision `34f17b0`. Each
time is a median of three runs to the first complete riverside scene at 320×180.
CPU uses default quality; GPU uses resident meshes, 1080p SSAA, snapping and smooth
presentation. Native starts a fresh process with executor caching disabled.
Browser uses a fresh context, local HTTP and an automatic Start click. OS,
browser-engine and GPU-driver caches are not flushed, and Internet latency is
excluded.

| Cartridge | PNG bytes | PNG KiB | Native CPU | Native GPU | Browser CPU | Browser GPU |
| --------- | --------: | ------: | ---------: | ---------: | ----------: | ----------: |
| Odin      |   277,334 |   270.8 |     1.20 s |     1.24 s |      0.98 s |      1.08 s |
| Luau      |   257,835 |   251.8 |     1.37 s |     1.43 s |      1.03 s |      1.11 s |

The browser player becomes ready in about 72–142 ms, before Start. After Start,
the scene takes about 0.87 s in CPU mode and 0.92–0.95 s in GPU mode. The staged
decoder/upload schedule consumes 51 simulation ticks, approximately 850 ms at
60 Hz. Odin intentionally mirrors the Luau decoding schedule. This is the demo's
loading policy, not a required startup delay for every cartridge.

PNG size excludes the player: browser runtime modules are 347,703 bytes (CPU)
or 348,157 bytes (GPU), and the shared Luau executor is 716,725 bytes. The scene
contains 33,806 submitted triangles after surface merging.

With a warm native executor cache, Luau reaches the complete scene in about
1.20 s CPU / 1.26 s GPU. Browser executor caching is scoped to the page: a full
reload does not report an application cache hit. Restarting within the same page
does reuse the compiled executor, verified by the benchmark's cache-hit checks.

Run `mise run validate bench:riverside:startup`. The retained report is
`build/riverside-startup/report.json`, including sizes, hashes, individual samples,
cache behavior and native stock-player image checks. The benchmark builds a
speed-optimized copy of native player sources under ignored build output, with
timing probes, neutral input and real-time smoke pacing. Timers begin at runtime
entry, excluding OS process/DLL loading; the native audio device is dummy. Window
presentation is included, but physical scanout is unmeasured. The stock player is
not edited. Browser timing observes the main-thread frame handler after canvas
delivery. The recorded snapshot's native and browser first-scene hashes matched
the stock player for both SDKs and backends. The task checks observer/stock
agreement natively, browser CPU/stock agreement, and cross-SDK agreement on each
browser backend. Builds finish before timing.

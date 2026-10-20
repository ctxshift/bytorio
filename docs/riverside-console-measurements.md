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
`/riverside/odin/build/web/player.html?renderer=gpu&ssaa=1080p&smooth-pan` or
the matching `/riverside/luau/` path. Both exports include PNG cartridges.
For native:

```text
build/compact-3d/riverside/odin/build/native/player.exe --renderer gpu --ssaa 1080p --smooth-pan
```

Hold Left to pan, Right to orbit, Up to move the rabbit, and Space for 640×360.
The default is 320×180. Releasing camera controls returns to the base view.
The source templates are `experiments/voxel-resolution/console-game.odin` and
`console-game.luau`; use the task to embed their generated scene data. These are
renderer qualification cartridges, not the viewer's full walking simulation.

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
stream and incrementally decodes it over 16 updates to preserve the native
instruction budget. Odin mirrors that loading schedule for exact replay parity.
This is an experiment-local encoding, not a new cartridge or asset protocol.
The PNG container, resource API and player limits are unchanged.

## Method and correctness

`build/compact-3d/riverside/performance.json` retains device/browser identity,
source and binary hashes, geometry, startup, memory and stage statistics.
Per-case raw JSON and 1080p presentation captures sit beside it.

Each case uses two warm-up passes and five measured passes. Each pass contains
86 updates; the first 56 are excluded from steady-state statistics, covering
decoding, all uploads and seven full-scene warm-up updates. The remaining 30
give 150 samples per SDK/host/motion/resolution. Native retains Wasmtime fuel
metering. Both hosts load PNGs and use GPU, 1080p SSAA, camera snapping and
smooth presentation. Cases cover pan and orbit at both outputs with rabbit motion.

The verifier compares every native/browser logical framebuffer hash and all
cross-SDK traces, checks expected triangle counts, verifies active 1920×1080
smooth presentation and rejects unexpectedly empty captures. Independent unit
fixtures check merging, signed coordinates, palette values, winding, duplicates
and compression overlap/window boundaries. Parity complements these independent
checks; it is not itself a visual reference.

Timing includes updates, resource transport/validation, draw commit, CPU mesh
processing, GPU submission/synchronization/readbacks, CPU composition and smooth
presentation preparation. Browser totals also include the frame-buffer copy.
Draw-commit timing includes rendering, not just command submission. Stage
percentiles must not be added to produce a total percentile.

Window presentation, Worker message delivery, canvas/compositor, scanout, audio
and a full gameplay simulation are excluded. Startup ends at the initial loading
frame before scene uploads finish; it is not time to a fully visible scene.
Resource work counters cover the final replay pass, including loading, while
steady-state timings exclude those frames. Process working set, guest/runtime
linear memory and resource budget bytes are different accounting domains.

## Results

Measured on 2026-10-20 on Windows x64 with an i7-11700K and RTX 3090, using
Chrome 155.0.8059.41 for the browser. The report enumerates browser GPU devices;
it does not separately record the native OpenGL adapter string. All eight cases
passed native/browser and cross-SDK logical pixel parity. Active smooth
presentation and the expected geometry counts passed. The 2,400 steady-state
samples all exceeded 16.67 ms; correctness passed, but `performance60Hz` did not.

Observed total p95 milliseconds, including the browser frame-buffer copy:

| SDK  | Output  | Motion | Native | Browser |
| ---- | ------- | ------ | -----: | ------: |
| Odin | 320×180 | Pan    |  44.17 |   70.80 |
| Odin | 320×180 | Orbit  |  43.56 |   70.60 |
| Odin | 640×360 | Pan    |  46.51 |   72.20 |
| Odin | 640×360 | Orbit  |  45.76 |   71.50 |
| Luau | 320×180 | Pan    |  45.27 |   71.20 |
| Luau | 320×180 | Orbit  |  44.35 |   71.40 |
| Luau | 640×360 | Pan    |  45.36 |   71.70 |
| Luau | 640×360 | Orbit  |  44.75 |   74.10 |

Updates reached approximately 0.10 ms native and 0.20 ms browser at p95. The
shared rendering work dominates: draw commit, including mesh processing and GPU
synchronization, reached about 19.91 ms native and 29 ms browser. The subsequent
raster/composition/presentation stage reached about 27.38 ms native and 43.80 ms
browser, with another 1.9–3.0 ms browser pixel copy. These are stage percentiles,
not additive parts of the total percentile. The presenter iterates over the
enlarged 1920×1080 image on CPU; the renderer also stages CPU-transformed triangles
and synchronously reads attachments back. This is a pipeline bottleneck, with
little timing separation between the cartridge languages.

Both output modes use roughly 2.1 million internal pixels including overscan,
then build the same 1080p presentation. Choosing 320×180 therefore saves little
with these settings. The earlier resident-geometry viewer's approximately 2 ms
GPU timings do not describe this console pipeline's total cost.

Observed guest linear memory was 3.50 MiB for Odin and 6.38 MiB for Luau; Luau
heap peak was 3.57 MiB, within the unchanged 4 MiB ceiling. Browser runtime linear
memory reached 43.00 MiB at the low output and 49.44 MiB at the high output.
Resource-budget peaks were 8.65/11.29 MiB, and native process working set was
approximately 106–118 MiB. These domains overlap or describe different processes;
do not sum them into a single memory requirement.

The explicit f32 view-matrix rounding in the Luau cartridge is intentional.
Odin's typed matrix rounds its elements before multiplication; retaining Luau
double precision until afterward changed edge pixels during orbit. Matching
the input precision restored exact traces without weakening comparison tolerances.

## Next backend gate

The backend still transforms/clips triangles on CPU, stages them each frame and
reads color/depth back for CPU composition. Smooth presentation also constructs
the enlarged output on CPU. Qualify versioned GPU-resident meshes, attachments
and final resolve/presentation next. Synchronize only for actual CPU consumers,
preserving rollback, depth, resource bounds and HUD composition. Keep the CPU
renderer for conformance and rerun these cartridges before claiming 60 fps or
qualifying integrated/mobile devices.

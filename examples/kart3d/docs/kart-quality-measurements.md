# Kart rendering quality measurements

The CPU quality renderer retains private supersampled attachments across
compatible mesh/material draws. Previously every batch expanded the complete
logical color/depth image and resolved the complete sample image. The polished
eight-kart scene submits roughly 106 batches per frame. The new path expands
and resolves once for each compatible sequence, preserving subpixel depth and
color until a real CPU consumer or commit requires logical pixels. CPU remains
the default; GPU acceleration and resident meshes require explicit selection.

## Method and limits

Run `mise run //examples/kart3d:benchmark:quality`. The example owns this task and
its benchmark script. Builds finish before serial native/browser measurements.
Both SDKs use the same fixed input replay and automatic kart LOD, with both
display sizes and SSAA off, 2× and up to 1080p. GPU cases enable resident meshes.
The 320×180 sample sizes are 320×180, 640×360 and 1920×1080; the 640×360 sample
sizes are 640×360, 1280×720 and 1920×1080 respectively.

Each of seven passes initializes the cartridge, advances 240 fixed simulation
updates without drawing, then renders 60 moving frames. Two passes warm the
pipeline; five produce 300 measured frames per configuration. CPU pixel hashes
and sound counts match between SDKs and native/browser. GPU sound traces match;
separate image-conformance checks qualify GPU raster differences. This replay
measures a moving race start, not the complete course or worst-case gameplay.

Times include update, resource submission, drawing, resolve and the existing
benchmark presentation work. Browser GPU timings wait for completion and bitmap
creation. Diagnostic pixel hashes run outside timed sections. Native CPU window
upload, browser main-thread delivery, audio, frame pacing and display scanout
are excluded. Computed work throughput is **not delivered display FPS**. All
timing policies still use the fixed simulation clock; its separate conformance
checks do not turn this benchmark into a display-delivery measurement.

Startup is a single local observation at 320×180, including for configurations
that subsequently switch to 640×360. Native CPU completes its first frame;
native GPU has submitted that draw but has not waited for presentation/completion.
Browser startup includes its first frame. Native executor caching remains
enabled; the browser benchmark supplies executor bytes without the launcher's
compiled-module cache. OS/browser caches are not cleared. Startup fields are not
cold-download latency distributions. Missing native guest heap exports appear
as zero, while browser missing exports appear as null; neither establishes live
heap usage. Guest linear memory, runtime linear memory, resource accounting,
CPU scratch, GPU estimates and native process memory overlap and must not be
added together. CPU traffic counts sample-buffer import writes and logical
resolve writes across the device lifetime, including warmup; resource statistics
can describe a different accumulation interval. GPU readbacks for diagnostic
hashes are outside timed work but appear in cumulative transfer counters.

The desktop used Windows x64, an Intel Core i7-11700K, 32 GiB installed RAM and an
NVIDIA GeForce RTX 3090. Chrome 155 used the NVIDIA adapter through ANGLE/D3D11.
This does not qualify lower-powered target hardware or guarantee 60 FPS.

## Repeated-resolve reproduction

A one-update static 320×180, CPU 2× replay was measured before and after retaining
samples, using two warmup and five measured passes. Its p95 total work times were:

| SDK  | Native before | Native after | Browser before | Browser after |
| ---- | ------------: | -----------: | -------------: | ------------: |
| Odin |     193.87 ms |     31.53 ms |      218.90 ms |      41.50 ms |
| Luau |     161.18 ms |     20.37 ms |      224.90 ms |      45.20 ms |

These tiny diagnostic samples establish the large repeated-work cost; they are
not moving-scene qualification or stable frame-rate distributions. Both runners
explicitly selected 2×; their timing arrays are retained separately from the
moving-scene matrix.

The independent regression checks deferred visibility, one import/resolve for
two draws, linear-light sample preservation, depth, CPU HUD barriers, clears,
readback, rollback, reset and quality invalidation. Ordinary CPU rendering
allocates no quality device. No shader or cartridge API change is needed.

The matrix also exposed one channel level in one pixel at tick 245, in the
640×360 / 1080p comparison. The custom Luau ground-shadow matrix had not been
quantized to f32 before multiplication, unlike the Odin matrix literal. The
Luau example now quantizes this constant once. Its draw packets and pixels
match exactly, with no tolerance change. This case is included in ordinary kart
conformance as well as the quality benchmark.

The benchmark supports `--resume <report.json>`. Reuse requires matching
recorded hardware/browser identifiers, timing method and SHA-256 hashes of the
cartridge, player, runtime and browser support files. Changed Luau exports were
measured again after the matrix fix; unchanged Odin exports reused their
completed measurements. Raw timings remain in their original local reports.

## Moving-scene results

Measured on 2026-10-21. Cells show **p50 / p95 / p99 milliseconds**; missed budgets count frames above 16.67 ms out of 300 measured frames. These are work timings, not delivered frame rates. The [portable summary](../../../docs/kart-quality-measurements.json) retains each startup, memory, traffic and artifact identity field; full timing arrays remain in the local benchmark reports.

### CPU

| SDK  | Display | SSAA  |                Native ms |               Browser ms | Missed native / browser |
| ---- | ------- | ----- | -----------------------: | -----------------------: | ----------------------: |
| odin | 320×180 | off   |       5.07 / 5.76 / 6.22 |       5.60 / 6.30 / 7.00 |                   0 / 0 |
| odin | 320×180 | 2x    |    15.98 / 22.15 / 23.79 |    35.80 / 41.20 / 45.80 |               100 / 300 |
| odin | 320×180 | 1080p | 108.52 / 118.19 / 124.63 | 154.80 / 173.80 / 196.80 |               300 / 300 |
| odin | 640×360 | off   |    17.14 / 20.63 / 23.70 |    19.20 / 21.40 / 24.30 |               239 / 300 |
| odin | 640×360 | 2x    |    52.49 / 60.69 / 75.24 |   80.90 / 88.60 / 112.90 |               300 / 300 |
| odin | 640×360 | 1080p | 109.35 / 122.77 / 142.69 | 153.70 / 166.50 / 180.50 |               300 / 300 |
| luau | 320×180 | off   |       5.79 / 6.60 / 8.27 |       6.30 / 7.20 / 7.80 |                   0 / 0 |
| luau | 320×180 | 2x    |    16.17 / 17.36 / 18.14 |    34.70 / 37.70 / 38.60 |                69 / 300 |
| luau | 320×180 | 1080p | 112.46 / 134.93 / 147.14 | 156.30 / 182.20 / 216.50 |               300 / 300 |
| luau | 640×360 | off   |    18.05 / 19.95 / 21.10 |    19.80 / 21.60 / 24.80 |               300 / 300 |
| luau | 640×360 | 2x    |    53.86 / 70.64 / 81.05 |  85.70 / 104.50 / 123.20 |               300 / 300 |
| luau | 640×360 | 1080p | 115.83 / 152.59 / 178.90 | 157.20 / 176.90 / 192.20 |               300 / 300 |

### Opt-in resident GPU

| SDK  | Display | SSAA  |             Native ms |            Browser ms | Missed native / browser |
| ---- | ------- | ----- | --------------------: | --------------------: | ----------------------: |
| odin | 320×180 | off   |    6.06 / 8.16 / 8.81 | 22.30 / 24.90 / 31.60 |                 0 / 300 |
| odin | 320×180 | 2x    |    6.06 / 8.78 / 9.28 | 22.30 / 24.30 / 30.20 |                 0 / 300 |
| odin | 320×180 | 1080p |    6.14 / 8.45 / 9.39 | 22.20 / 24.50 / 29.70 |                 0 / 300 |
| odin | 640×360 | off   |  8.39 / 12.05 / 12.75 | 23.40 / 26.20 / 31.70 |                 0 / 300 |
| odin | 640×360 | 2x    |  9.54 / 11.82 / 12.92 | 23.60 / 26.50 / 31.60 |                 0 / 300 |
| odin | 640×360 | 1080p |  8.52 / 11.75 / 12.87 | 23.90 / 29.20 / 32.90 |                 0 / 300 |
| luau | 320×180 | off   |  8.69 / 11.03 / 14.47 | 22.20 / 26.00 / 32.20 |                 0 / 300 |
| luau | 320×180 | 2x    | 10.24 / 13.58 / 14.69 | 23.20 / 26.10 / 32.50 |                 1 / 300 |
| luau | 320×180 | 1080p |  9.75 / 13.56 / 14.94 | 25.30 / 40.00 / 56.90 |                 0 / 300 |
| luau | 640×360 | off   | 12.28 / 16.71 / 22.34 | 24.00 / 30.00 / 34.90 |                16 / 300 |
| luau | 640×360 | 2x    | 10.58 / 13.07 / 14.38 | 22.80 / 27.60 / 34.70 |                 1 / 300 |
| luau | 640×360 | 1080p | 13.63 / 16.46 / 17.68 | 27.90 / 34.30 / 37.70 |                 9 / 300 |

### Startup and memory observations

The following rows use 320×180. Startup is native / browser ms, with the completion and cache limits described above. Memory values are MiB.

| SDK / path       | PNG bytes |     Startup ms | Guest linear | Browser runtime linear | Native working set |
| ---------------- | --------: | -------------: | -----------: | ---------------------: | -----------------: |
| odin / cpu off   |   250,530 |  80.61 / 42.50 |         3.19 |                  17.94 |              24.76 |
| odin / gpu 1080p |   250,530 | 369.31 / 81.90 |         3.19 |                  28.94 |             101.60 |
| luau / cpu off   |   246,875 | 50.82 / 123.90 |         6.50 |                  17.94 |              23.43 |
| luau / gpu 1080p |   246,875 | 392.31 / 92.20 |         6.50 |                  28.94 |              98.89 |

Ordinary CPU reports zero quality-device bytes. CPU 2× at 320×180 uses 1.83 MiB of quality scratch. Its 44,630 material/mesh batches share 421 attachment sequences across startup and seven passes: one import and resolve per rendered frame, rather than about 106 per frame.

## Remaining qualification

The repeated attachment work is removed, but CPU supersampling is still too expensive for a 60 Hz work budget in this material-heavy scene. CPU 320×180 without SSAA fits the measured budget; 640×360 CPU and supersampled CPU cases generally do not. Odin native resident GPU p95 fits at every tested quality. Luau native GPU generally fits, but its 640×360 / SSAA-off p95 of 16.71 ms narrowly exceeds budget; several p99 values and individual frames also miss. Browser resident GPU p95 remains above budget even without SSAA. Its weak sensitivity to SSAA points toward non-fill work as a profiling target, without establishing the precise cause.

The next measurements need lower-powered hardware, a full-course workload, actual delivered-frame distributions, and completed native GPU startup timing. Browser launcher cache behavior also needs its own startup comparison. These results do not establish a minimum-device 60 FPS guarantee, and GPU acceleration remains opt-in.

# Compact 3D measurements

Run `mise run test:3d` to reproduce the native/browser comparison and regenerate
`build/compact-3d/report.json`, per-workload raw samples and player captures.
See the [implementation and SDK contract](../../compact-3d.md) for supported scope.

## Method

Reference environment: Windows x64, Intel Core i7-11700K, Odin dev-2026-10
(84bc3fc), Wasmtime 49.0.3, Luau 0.743 and headless Chromium 156.0.8078.4.
These are local reference measurements, not minimum-device qualification.

Each workload contains 24 updates. Two warm-up passes precede five measured
passes, giving 120 timing samples per SDK/host/workload pair. Every pass starts
with fresh resource initialization. Reported CPU totals combine update, draw
submission/validation/rasterization and presentation-buffer preparation. They
exclude SDL display, browser canvas presentation, audio output and browser pixel
transfer/copy time; raw browser records include that copy as a fourth timing field.
Native guest execution retains Wasmtime fuel metering.

The native benchmark uses the actual standalone player and PNG cartridge. Browser
benchmarks use the actual player Worker with loose payloads. Separate interactive
PNG loads, 120-tick smoke runs and warm cartridge replacements exercise the full
browser player. Both SDKs, hosts and all ten workload/resolution pairs produced
identical framebuffer hashes for the captured replay traces. Resource storage and
3D work counters also matched. The first recorded run is summarized below and
retained in [the reference snapshot](compact-3d-reference.json). Timing is noisy
and should be regenerated on a target device before making a budget claim.

## Frame CPU cost

Observed p95 milliseconds; 16.67 ms is the nominal CPU budget for 60 Hz before
display, input, audio and scheduling overhead:

| Workload | Resolution | Odin native | Luau native | Odin browser | Luau browser |
| --- | --- | ---: | ---: | ---: | ---: |
| Room, character, rotating prop, mesh and HUD | 320×180 | 2.35 | 2.22 | 2.70 | 3.00 |
| Same scene | 640×360 | 8.16 | 7.36 | 8.00 | 8.10 |
| One cell edit plus full room surface rebuild each update | 320×180 | 2.51 | 2.30 | 2.80 | 2.80 |
| Same edits | 640×360 | 7.29 | 7.41 | 8.30 | 8.10 |
| Add 16³ checkerboard volume | 320×180 | 9.57 | 10.18 | 16.50 | 16.40 |
| Same checkerboard | 640×360 | 18.52 | 18.55 | 30.20 | 25.70 |
| Add 64 shared prop instances | 320×180 | 5.97 | 6.23 | 9.50 | 10.20 |
| Same instances | 640×360 | 11.46 | 11.63 | 15.20 | 15.50 |
| Perspective camera | 320×180 | 1.76 | 2.17 | 2.30 | 2.30 |
| Same perspective scene | 640×360 | 5.18 | 5.18 | 6.30 | 6.00 |

The normal scene submits 1,426 triangles per frame. The checkerboard adds 24,576
triangles despite occupying only 4,096 bytes of source cells. This makes surface
complexity a better predictor than cell storage alone. The small room edit path's
native p95 update cost was approximately 0.07 ms in either SDK; that includes
guest update, packet copying/validation and remeshing. It is not an isolated mesher
timing or evidence for a large frequently edited world.

Differences between SDK timings at these scales are small and sometimes reverse
between runs. Most work executes in the same Odin renderer. The 640×360
checkerboard exceeds a 60 Hz CPU budget on both hosts; browser 64-instance stress
also leaves little scheduling headroom. The ordinary scene is comfortably below
that budget on this reference CPU, without establishing a universal frame rate.

A subsequent full regression run retained exact pixel/accounting parity but
measured 640×360 checkerboard p95 at 22.62/27.67 ms native and 29.40/32.40 ms
browser for Odin/Luau respectively. Browser 64-instance p95 reached 16.70/17.20 ms.
This variation reinforces the need to qualify a target device rather than infer
a reliable frame rate from one favorable run. The current raw report and the
first-run reference snapshot intentionally preserve distinct observations.

## Memory

Both SDKs produced identical host resource accounting:

- Source voxel cells: 5,168 bytes across room, prop, checkerboard and two character
  frames. All are resident even when a particular stress asset is not drawn.
- Cached generated geometry plus the ordinary mesh: 1,151,720 bytes.
- Two depth attachments: 1,152,000 bytes, for both supported display modes.
- Normal 320×180 retained resources: 2,770,904 bytes; transaction peak 3,463,316.
  These include screen/output data and the previous versions retained for atomic
  publication. Geometry, depth and staging are charged as well as source cells.
- Odin guest linear memory: 3,342,336 bytes. Luau executor linear memory:
  4,456,448 bytes, with roughly 1.26 MB live/peak Luau heap after the replay.
- Browser renderer linear memory after the normal replay: 19,595,264 bytes. This
  is allocated linear memory, not the same measure as live resource-budget bytes.

The captured normal native process working set was about 24.6 MB for Odin and
22.5 MB for Luau; those snapshots include engine code, allocator state and OS
accounting. They do not imply Luau has a smaller language runtime. Process RSS,
linear memory and resource-budget bytes are not interchangeable.

This workload does not activate the typed audio engine. Its fixed 55,463,952-byte
reservation still applies within the shared 64 MiB resource budget when activated.
Qualify simultaneous 3D/audio stress before publishing combined limits; this
benchmark does not establish a full DSP workload's timing or memory headroom.

## Startup and executor reuse

Single local observations, in milliseconds:

| SDK | Native executor cache disabled | Native cache-enabled run | Browser first PNG load | Browser same-page replacement |
| --- | ---: | ---: | ---: | ---: |
| Odin | 17.31 | 18.26 | 24.40 | 17.00 |
| Luau | 174.81 | 22.91 | 71.90 | 27.30 |

The executor cache applies to Luau; Odin has no Luau executor to reuse. The native
Luau compile portion fell from 159.74 ms to 6.63 ms. Browser replacement reported
an executor cache hit and avoided recompiling/downloading it, but still created a
new VM, compiled the game source and rebuilt resources. Browser first-load numbers
include local fetching and first-frame rendering; native startup is measured by
the player's existing startup clock. These are different clocks, not a precise
cross-host loading contest. OS/browser code and filesystem caches were not flushed.

## Conformance and next decisions

Focused tests cover depth ordering, six-plane clipping paths, invalid mesh
indices/nonfinite transforms, stale sessions, old-protocol rejection, color/depth
rollback, voxel interior-face culling, region-edit rollback, palette lifetime and
opacity, resource allocation limits, excessive surfaces and rebuild-work limits.
Language checks, generated constants and existing SDK/cartridge/graphics/audio
and legacy game replay suites remain required regression gates.

Keep the 3D profile experimental. The next useful optimizations are transformed
vertex reuse and cheaper raster work, then measuring a shared accelerated backend
if target devices need it. Coplanar face merging should reduce suitable solid
models; it cannot eliminate the isolated cells in the checkerboard. Chunking can
bound large-world edit cost, but will not reduce all surface rendering costs.
Textures, richer materials, streaming and combined audio/3D qualification remain
future work. No external engine implementation was incorporated.

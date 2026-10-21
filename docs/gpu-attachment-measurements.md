# GPU attachment measurements

Measured on 2026-10-21 with Windows x64 native OpenGL and browser WebGL2 in
installed Chrome. The workload is the original imported rigid-model fixture:
a rotating textured body and separately animated wheel, rendered at 320×180 with
a CPU text HUD. It exercises two material batches per frame through both SDKs.
It is a small renderer proxy, not a complete racing game or a minimum-device
qualification. GPU acceleration and resident geometry were explicitly enabled.

## Compatible-batch residency

The baseline preserves player exports from before attachment residency
(source revision `b35d4b3`). Both versions load the same newly built PNG cartridge,
not their separately compiled guest payloads. Native/browser traces agree at each
setting, and direct-render traces also agree between old and new players.

Each runtime executes seven 32-frame turning replays. The first two are warmups;
the table reports the median sum of measured update, draw and presentation phases
from the remaining 160 frames. Browser presentation includes bitmap creation and
GPU completion, but not the main page compositor. Native timings include GPU
completion and exclude interactive window delivery and audio playback. Runs were
sequential, without concurrent builds/tests. These short, single-session timings
show local overhead changes, not stable maximum playable frame rates.

| SDK | SSAA | Native before → after (ms) | Browser before → after (ms) |
| --- | --- | --- | --- |
| Odin | Off | 1.229 → 0.906 | 2.100 → 1.600 |
| Luau | Off | 1.672 → 1.372 | 2.900 → 1.700 |
| Odin | 1080p | 1.370 → 1.052 | 2.700 → 1.800 |
| Luau | 1080p | 1.637 → 1.379 | 2.700 → 1.900 |

Two compatible batches now share one upload/readback pair instead of two.
The counters record 450 batches in 225 sequences, including the initial frame
and all warmup/replay frames. Each direction transfers 460,800 attachment bytes
per frame, rather than 921,600: a 50% reduction. Browser total texture uploads
fall from 259,200,256 to 155,520,256 bytes in this replay. The unchanged final
presentation upload explains why that total falls by 40%, rather than 50%.

Both hosts report 16 geometry uploads and 434 cache hits, with uploads occurring
when benchmark initialization creates new resource versions. Unchanged geometry
continues to be reused within each cartridge lifetime.

Attachment input/scratch allocation is 1,612,800 bytes with SSAA off and
25,804,800 bytes at 1080p. This storage is distinct from transferred bytes,
geometry/material caches, CPU snapshots and final presentation storage. Browser
`textureBytes` already includes attachment storage. These are allocation
estimates, not measurements of driver memory.

## Direct committed presentation

A second comparison preserves the compatible-batch player at `cf4226c`, before
direct committed presentation, and uses the same method and identical current
cartridge bytes on both players. These are separate sequential runs from the
first table; compare within each table rather than across sessions.

| SDK | SSAA | Native before → after (ms) | Browser before → after (ms) |
| --- | --- | --- | --- |
| Odin | Off | 0.757 → 0.702 | 1.600 → 1.200 |
| Luau | Off | 1.274 → 0.715 | 1.600 → 1.100 |
| Odin | 1080p | 0.934 → 0.860 | 3.200 → 1.300 |
| Luau | 1080p | 1.356 → 1.044 | 1.800 → 1.200 |

The 225 frames now publish 225 GPU snapshots. Native presents 224 times because
its initialization frame is not displayed; the browser presents all 225.
Readbacks fall from 103,680,000 to 14,745,600 bytes (85.8%). All remaining
readbacks are the 32 explicit logical diagnostic hashes in one replay, outside
the measured phases. Ordinary eligible frames perform no world readback or
final world upload. Initial attachment uploads remain 103,680,000 bytes; this
change does not retain per-sample depth across separate transactions.

Opaque HUD composition currently uploads full logical color/mask textures:
288,000 bytes per frame, compared with the old 230,400-byte final color upload.
Thus browser total texture uploads rise 8.3%, from 155,520,256 to 168,480,256
bytes, while total attachment readback plus texture upload falls 29.3%.
This is an explicit tradeoff, not a zero-transfer claim. Sparse HUD upload
regions could reduce it later. A world-only frame uploads no HUD textures.

The two committed snapshot slots allocate 1,497,600 bytes at this logical
resolution, including color, packed depth and HUD color/mask. This cost is
independent of SSAA, additional to working attachments, and already included
in browser `textureBytes`. Geometry reuse is unchanged: 16 uploads and 434 hits.
Native/browser output traces agree, and SSAA-off traces match the baseline.

The full riverside cartridge also passes both SDKs/native/browser at 320×180
and 640×360 with resident geometry, 1080p SSAA, snapping and smooth presentation.
Five measured 30-frame pan and orbit replays follow two warmups, excluding each
replay's 58 loading/settling frames. The table shows the larger p95 of pan/orbit:

| SDK | Logical width | Native p95 (ms) | Browser p95 (ms) |
| --- | --- | --- | --- |
| Odin | 320 | 3.347 | 4.600 |
| Odin | 640 | 4.725 | 4.600 |
| Luau | 320 | 3.353 | 3.700 |
| Luau | 640 | 5.143 | 4.600 |

Every measured sample stays below 16.67 ms on this machine. These timings include
GPU completion and exclude window/compositor/scanout, audio and Worker delivery;
they do not establish delivered 60 FPS on other hardware. Same-host SDK hashes
match exactly; cross-host pixels satisfy the existing bounded SSAA edge tolerance.
Each run publishes/presents 266 GPU frames with zero HUD upload bytes. Explicit
logical diagnostics still read snapshots; CPU loading frames also upload their
presentation. Run `mise run bench:riverside`; its raw report is
`build/compact-3d/riverside/performance.json`.

## Reproduction and limits

Preserve the older exports before rebuilding, then run from the repository root:

```text
mise run bench:attachments -- --baseline <old-export-root>
```

The old root must contain `odin/build/native`, `odin/build/web` and equivalent
`luau/build` exports. Current cartridges are built by the task and supplied to
both players. Reports under `build/attachment-benchmarks/` retain raw timings,
traces, counters and SHA-256 fingerprints of cartridge/player/runtime/device
files. Without `--baseline`, the task qualifies and measures the current players.

Independent native/browser device fixtures verify deferred CPU visibility,
interior color/depth, all three SSAA settings, transfer counts, invalid
continuations and recovery. A device that withholds CPU writes independently
tests load-pass continuity, CPU HUD ordering, clears, offscreen targets,
readbacks, stale handles and rollback after draw/synchronization failures.
Textured-mesh, billboard and imported-model GPU integration suites exercise both
SDKs, streamed/resident geometry and native/browser hosts.

Direct snapshot fixtures independently check displayed world/HUD pixels, lazy
color/depth reads, version isolation, repeated presentation without transfers,
and invalidation at all three qualities. Common transaction tests cover staging,
publication and read failures, late rejection, destruction, offscreen readback,
HUD/3D ordering and partial-alpha fallback. Browser fixtures additionally inject
real context loss. Hashes and captures intentionally restore logical CPU data.

Clears, target switches and CPU consumers synchronize conservatively. Multiple
screen batches retain the existing restrictions on smooth presentation. A
representative complete racer and integrated/mobile GPU qualification remain
separate work; the fixture cannot establish their performance. CPU rendering
remains the default and its conformance remains independent of GPU availability.

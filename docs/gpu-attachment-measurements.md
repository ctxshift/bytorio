# GPU attachment measurements

Measured on 2026-10-21 with Windows x64 native OpenGL and browser WebGL2 in
installed Chrome. The workload is the original imported rigid-model fixture:
a rotating textured body and separately animated wheel, rendered at 320×180 with
a CPU text HUD. It exercises two material batches per frame through both SDKs.
It is a small renderer proxy, not a complete racing game or a minimum-device
qualification. GPU acceleration and resident geometry were explicitly enabled.

## Comparison

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

Residency currently ends at CPU consumers and transaction publication. Final
presentation still uploads the committed logical snapshot. Clears and target
switches synchronize conservatively, and multiple screen batches retain the
existing restrictions on smooth presentation. Direct publication/presentation,
a representative complete racer and integrated/mobile GPU qualification remain
separate work. CPU rendering remains the default and its conformance remains
independent of GPU availability.

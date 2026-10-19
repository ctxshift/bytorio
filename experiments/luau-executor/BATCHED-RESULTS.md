# Batched drawing and cached executor results

Recorded 2026-10-19 on the same Windows x64 / Core i7-11700K / Chrome 155 desktop as the [rectangle baseline](RESULTS.md), using Wasmtime 49.0.3. Five processes/workers per variant, two warmup passes and five measured passes per instance: **3,350 timed frames per variant**. Measurements ran serially. [Numeric snapshot](results-batched.json), [drawing protocol](BATCHING.md), [cache behavior](CACHING.md).

## Before and after

Mean CPU frame work includes game update, command generation/validation/copy, and shared software rendering. It excludes presentation, audio delivery, hashing, Worker messaging, and the separately measured browser framebuffer copy. Cached and cold code execute the same commands; caching primarily changes startup.

| Workload | Original rectangle path | Batched path, cached executor | Change |
| --- | ---: | ---: | --- |
| Native Luau, metered | 4.762 ms/frame | 0.276 ms/frame | About 17× less CPU time |
| Browser Luau | 3.501 ms/frame | 0.182 ms/frame | About 19× less CPU time |
| Native Odin, metered | 0.209 ms/frame | 0.201 ms/frame | Roughly unchanged |
| Browser Odin | 0.137 ms/frame | 0.120 ms/frame | Small improvement |
| Native Luau startup | 166.80 ms, no cache | 10.42 ms, warm cache | Compilation avoided on reuse |
| Browser Luau startup | 32.50 ms, no application cache | 8.40 ms, warm page cache | Compiled code and bytes reused |

The initial scene now sends **255 commands instead of 8,582**. Its sprites and text are expanded in the shared Odin renderer, using a cartridge-owned atlas/font uploaded once. All 134 quest frames and 76 defeat/recovery frames retain the pre-optimization hashes and sound-request counts in `tests/rpg/parity.json`.

These are observations from two runs on one desktop, not isolated language speed measurements. The browser loader also changed to asynchronous module preparation and sharing; engine caching/tiering contributes to startup behavior. No low-end/mobile performance claim is made.

## Current variants

| Host / execution | Cartridge | Mean frame work | Frame p95 | Median startup |
| --- | --- | ---: | ---: | ---: |
| Native, metered | Odin | 0.201 ms | 0.255 ms | 8.49 ms |
| Native, metered | Luau, cold cache | 0.274 ms | 0.336 ms | 194.89 ms |
| Native, metered | Luau, warm cache | 0.276 ms | 0.351 ms | 10.42 ms |
| Native, unmetered benchmark | Odin | 0.201 ms | 0.254 ms | 6.67 ms |
| Native, unmetered benchmark | Luau, cold cache | 0.258 ms | 0.313 ms | 148.02 ms |
| Native, unmetered benchmark | Luau, warm cache | 0.259 ms | 0.324 ms | 8.95 ms |
| Chrome Worker | Odin | 0.120 ms | 0.200 ms | 5.40 ms |
| Chrome Worker | Luau, bypass page cache | 0.181 ms | 0.300 ms | 21.00 ms |
| Chrome Worker | Luau, warm page cache | 0.182 ms | 0.300 ms | 8.40 ms |

Cold native Luau still incurs compilation and cache population: 191.05 ms median module compilation versus 6.62 ms cached module loading. Luau source/VM initialization remains about 1.7 ms in either native case. Cold starts are not eliminated; the cache helps subsequent loads of the same executor/configuration. All five warm native cases reported a cache usage count of two.

All five cached browser loads reported `hit: true`, `compileMs: 0` for the executor, and `downloadedExecutor: false`. Median Worker creation-to-ready time including page-side preparation was **16.3 ms**. The table's browser startup metric includes page-side executor preparation and Worker-side loading through first framebuffer, while excluding Worker creation/message delivery. Native startup remains measured inside the player, before reading module/source files through first framebuffer; it excludes executable/DLL loading. Compare startup within a host. Browser cold controls cannot flush internal engine caches.

## Frame work and memory

Native metered Luau submission dropped from 4.690 ms to **0.076 ms**, including validation and buffer copies. Game update averages 0.002 ms. The shared renderer now costs about **0.198 ms** for either language. It does more work than the old rectangle renderer because sprite/font expansion moved into it, which largely offsets Odin's submission savings. The remaining native gap is about **0.075 ms/frame**, rather than a broad 23× language difference.

Browser cached Luau averages 0.062 ms for submission and 0.117 ms for rendering; Odin averages 0.0035 ms and 0.116 ms. Final framebuffer copying adds about 0.093 ms and 0.092 ms respectively, outside the frame-work totals.

| Memory measure | Odin | Luau, cold cache | Luau, warm cache |
| --- | ---: | ---: | ---: |
| Allocated guest linear memory | 1.5625 MiB | 2 MiB | 2 MiB |
| Native working-set median, metered, after replay | 19.1 MiB | 29.4 MiB | 17.1 MiB |
| Native maximum observed peak working set, metered | 21.0 MiB | 136.4 MiB | 19.6 MiB |

The browser renderer's separate linear memory is now **2.5625 MiB** for either guest, including atlas and both command formats. The tracked Luau heap peaks at about **687 KiB**; it is already part of the 2 MiB guest allocation. Browser cached bytes and compiled code are additional player-side memory, not included in guest allocation. Native working sets cover the full headless process, including Wasmtime and JIT/cache activity; peak compilation residency differs sharply from steady replay residency. Total browser process RAM is unmeasured.

The current executables/source bundles are about 14.1 KiB for the Odin cartridge and 15.1 KiB for the Luau cartridge. The shared player-supplied executor is about 694 KiB; it is not duplicated in cartridges.

## Reproduce and interpret

```text
npm run build:unified
node experiments/luau-executor/verify-drawing.mjs
node experiments/luau-executor/verify-cache.mjs
npm run bench:unified
```

Use `PLAYER_BROWSER_CHANNEL=chrome` for an installed Chrome. Raw data goes to `build/unified-player/benchmark-batched/`. The harness creates unique native cache directories without deleting existing caches. It verifies both native SDL render/audio paths, browser input/audio, Luau diagnostics, buffer validation, cache reuse/invalidation, and fresh game state. The original hello reproduction's recovery tests also pass.

The implementation now makes Luau practical for this RPG with little absolute CPU cost. It does not settle performance for vehicle simulation, world streaming, traffic, or allocation-heavy gameplay. Those remain separate workloads to measure before choosing a default language for more demanding cartridges.

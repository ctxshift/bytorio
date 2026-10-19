# Racing cartridge comparison

Measured on 2026-10-19 with an Intel Core i7-11700K, Windows x64, Chrome
155.0.8059.41, Odin dev-2026-10 (84bc3fc), Wasmtime 49.0.3 and the pinned Luau
Wasm executor. Both cartridges use the **same Odin player and shared renderer**
at **320×180**. Native uses the normal fuel-metered execution policy.

| Host | Cartridge | Mean CPU frame | p95 CPU frame | Startup, cache bypassed | Startup, executor cached |
| --- | --- | ---: | ---: | ---: | ---: |
| Native | Odin | 0.046 ms | 0.078 ms | 50.2 ms | — |
| Native | Luau | 0.212 ms | 0.516 ms | 168.9 ms | 11.7 ms |
| Browser | Odin | 0.093 ms | 0.200 ms | 7.7 ms | — |
| Browser | Luau | 0.231 ms | 0.500 ms | 30.5 ms | 9.2 ms |

The frame figures use the cached Luau samples; bypassing its code cache produced
similar steady-state frame times. Odin is approximately **4.6× faster on native**
and **2.5× faster in the browser** in this workload. Both CPU workloads are well
below a 16.67 ms tick on this desktop. This is not a measured end-to-end FPS rate,
and does not establish performance on mobile or low-power devices.

## Where the time goes

| Host / cartridge | Simulation | Drawing / submission | Shared rasterization | Pixel copy, additional |
| --- | ---: | ---: | ---: | ---: |
| Native / Odin | 0.0003 ms | 0.0121 ms | 0.0337 ms | — |
| Native / Luau, cached | 0.0027 ms | 0.1751 ms | 0.0337 ms | — |
| Browser / Odin | 0.0006 ms | 0.0125 ms | 0.0803 ms | 0.0741 ms |
| Browser / Luau, cached | 0.0029 ms | 0.1487 ms | 0.0797 ms | 0.0725 ms |

Most of the difference comes from generating drawing commands. The rasterizer's
cost is nearly identical within each host, as expected from the shared path.
Luau still calls its C graphics bindings for individual commands while building
the batch inside Wasm. The simulation itself is inexpensive in both languages.
Browser timer granularity limits interpretation of the smallest phase values.

## Memory and size

| Item | Odin cartridge | Luau cartridge + executor |
| --- | ---: | ---: |
| Guest linear memory | 1.5625 MiB | 2 MiB |
| Peak Luau allocator usage, inside guest memory | — | 670 KiB |
| Native process working set, median | 22.1 MiB | 17.2 MiB with executor cache |
| Cartridge bytes | 160,354 Wasm | 10,269 bundled source |
| Player-provided executor bytes | — | 711,359 Wasm |

The browser's shared Odin renderer reserves **3.125 MiB** of additional linear
memory for either language. The native renderer lives inside the process working
set. Active low-resolution pixel transfers are 225 KiB/frame; the renderer reserves
the maximum framebuffer so switching modes does not require reallocating it.
Guest memory figures exclude compiled code, JS/browser objects, stack reservations
outside the guest and GPU/display buffers. Working-set figures are process-wide
and do not imply that Luau uses less guest memory.

## Method and limitations

- Three serial samples per variant; 720 frames per replay; two warmup and five
  measured passes per sample, totaling 10,800 measured frames per row.
- Native compiles Odin's module on each process launch. Only the Luau executor is
  cached by the current player. Its cached startup is therefore not an equal-cache
  language comparison; the bypassed startup columns are the useful baseline.
- Browser cache hits reuse a compiled executor in the owning page and instantiate
  fresh guest memory in a new Worker. Cache bypass does not clear OS file caches
  or the browser engine's internal compilation caches. Browser timings use a local
  HTTP server, not the public tunnel.
- Both source compilation and game initialization are included on every Luau load.
  The cache stores executor code, not Luau game state or precompiled cartridge code.
- CPU frame time includes update, command submission and software rasterization.
  It excludes hashes, native display/audio, browser canvas painting and scheduling.
  Browser framebuffer copies are measured separately, not included in the table.
- This road-and-billboard workload does not predict the performance of a future
  mesh-based 3D renderer, large RPG, pathfinding system or larger asset set.

Full race and handling replays match across languages and hosts. See the
[demo guide](../../docs/racing-demo.md) for checks and reproduction commands.
The portable [measurement summary](results.json) is checked in; raw samples and
traces remain under `build/racing-player/benchmark/`.

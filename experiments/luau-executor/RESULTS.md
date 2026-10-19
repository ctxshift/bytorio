# Unified player experiment results

Recorded 2026-10-19 on Windows x64, Intel Core i7-11700K, Chrome 155.0.8059.41, Wasmtime 49.0.3, Emscripten 6.0.12, and Odin dev-2026-10 (`84bc3fc`). Five fresh processes/workers per variant; 3,350 measured quest frames per variant after warmup. [Method and reproduction](README.md).

The unified architecture works: both RPG cartridges run through the same Odin native executable and the same browser player/runtime. All framebuffer hashes and sound-request counts match over the 134-tick quest and 76-tick defeat/recovery routes. Native SDL rendering/audio queuing, browser keyboard/audio, and Luau source diagnostics also passed.

## Execution and startup

Frame work includes update, drawing/command submission, and software rendering. These figures exclude presentation, audio delivery, hashing, Worker messaging, and browser framebuffer copying. Startup boundaries differ between native and browser; compare languages within a host.

| Host / metering | Cartridge | Mean frame work | Frame p95 | Median startup |
| --- | --- | ---: | ---: | ---: |
| Native, fuel enabled | Odin | 0.209 ms | 0.259 ms | 7.53 ms |
| Native, fuel enabled | Luau executor | 4.762 ms | 5.346 ms | 166.80 ms |
| Native, fuel disabled for benchmark | Odin | 0.154 ms | 0.190 ms | 6.69 ms |
| Native, fuel disabled for benchmark | Luau executor | 3.966 ms | 4.311 ms | 126.66 ms |
| Chrome Worker | Odin | 0.137 ms | 0.200 ms | 5.20 ms |
| Chrome Worker | Luau executor | 3.501 ms | 3.900 ms | 32.50 ms |

For native fuel-enabled runs, median Wasm compilation took 6.50 ms for Odin and 159.17 ms for the shared Luau executor. Game initialization, including compiling Luau source, took approximately 0.003 ms and 1.83 ms respectively. The current player recompiles the executor on each launch. Caching that compiled module could avoid much of the Luau cold compilation cost; the cached path has not been implemented or measured.

Browser Worker creation-to-ready medians were 13.5 ms for Odin and 41.2 ms for Luau. The first measured Luau Worker reported 57.1 ms of internal startup, versus 31.8–34.2 ms on subsequent workers; local fetch and browser caching/tiering affect those observations. Browser initialization includes 16.5 ms median Luau source compilation/VM initialization; its first draw is also slower than warmed drawing.

## Where frame time went

| Mean phase | Native Odin, metered | Native Luau, metered | Browser Odin | Browser Luau |
| --- | ---: | ---: | ---: | ---: |
| Game update | 0.00034 ms | 0.00357 ms | 0.00015 ms | 0.00367 ms |
| Draw, validate, copy commands | 0.143 ms | 4.690 ms | 0.061 ms | 3.412 ms |
| Shared software renderer | 0.065 ms | 0.068 ms | 0.076 ms | 0.085 ms |

The dominant difference is **guest-side sprite/text command generation**, not the shared renderer or this RPG's gameplay logic. The Luau helpers traverse palette strings and make thousands of rectangle API calls per frame. A sprite/text API operating on resource handles and batches is a concrete optimization opportunity. These results do not establish a universal 23–26× language speed difference or predict the performance of racing physics, streaming, traffic, or a larger RPG.

Browser copying of the final framebuffer added approximately 0.092 ms for Odin and 0.085 ms for Luau, outside the table's frame totals. Real presentation and frame scheduling still add work. Both options fit inside a 16.67 ms frame budget for this scene on this desktop; low-end/mobile hardware remains untested.

## Memory and distribution

| Measure | Odin cartridge | Luau executor + cartridge |
| --- | ---: | ---: |
| Guest allocated linear memory, native/browser | 1.375 MiB | 2.000 MiB |
| Tracked Luau VM live / peak heap | Unavailable | 674 / 706 KiB |
| Native working-set median, metered, after replay | 19.0 MiB | 28.5 MiB |
| Native maximum observed peak working set, metered | 21.2 MiB | 129.2 MiB |
| Per-cartridge executable/source, with these bundled assets | 15.1 KiB Wasm | 15.9 KiB source |
| Additional shared executor carried by player | None | 692.4 KiB Wasm |

The common browser renderer adds 1.750 MiB of allocated linear memory to either option. Native working sets include the whole player, Wasmtime, generated machine code, and compilation allocations. The Luau peak is dominated by executor compilation and should not be interpreted as steady live cartridge memory. Unmetered native working-set medians were 18.6 MiB and 27.0 MiB respectively. Browser resident process memory was not measured.

Wasm linear-memory allocation includes static storage, stack, free allocator space, the VM, and source/compiler allocations; it is not equivalent to live heap or committed physical memory. The executor did not grow beyond its initial 2 MiB during these tests. Both modules declare an 8 MiB maximum. The Luau VM's tracked heap is a subset of its linear memory; it must not be added again to that total. The interpreter is shared player code, so its 692 KiB is not a cartridge-size penalty for every game.

## Decision supported

Keep a shared Wasm cartridge interface and Odin graphics/audio backend as a viable design. The prototype successfully removes the need for a separate native Luau integration. Odin currently leaves substantially more CPU headroom in this workload, while the Luau path is already usable for this small RPG.

Before treating this as a final performance decision, implement a shared batched sprite/text interface, measure a simulation-heavy 3D scene, and measure executor-module caching. Also evaluate source debugging and low-end browser behavior. Permanent dual-language support, the final runtime-language decision, and the PNG cartridge format remain separate product decisions.

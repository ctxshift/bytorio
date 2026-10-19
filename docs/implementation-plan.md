# Implementation plan

Status: updated 2026-10-19. The first Milestone 1 slice is implemented: a standalone native player and browser Wasm build run the same Luau example with one sprite and one sound. SDK commands and later milestones remain planned. See [the development guide](development.md) for actual build/run commands.

Current evidence: native core contracts and a live SDL smoke scenario pass on Windows; browser loading, keyboard movement, audio startup/stall behavior, and matching scripted framebuffer output have been checked in Chrome. Runaway execution, memory exhaustion, and source/runtime errors have explicit checks. CI configuration is included but has not yet run remotely. Physical controller/touch-device validation, a named minimum-device benchmark, streaming audio, and other desktop platforms remain open; this slice does not declare the entire machine profile complete.

Follow the [architecture](architecture.md). Preserve the accepted Luau/C++ stack, standalone native host, browser target, 384 x 216 screen, and 2D-first emphasis. The [3DS comparison](target-comparison.md) is advisory until a different scope is explicitly selected.

The product name remains undecided. Use neutral terminology in docs and code comments; avoid codename-derived namespaces, format markers, and extensions. All `sdk` command examples below are executable placeholders. Distribution must include self-contained PNG cartridges containing the full ROM and visible cover art.

## Delivery approach

Build a playable vertical slice before a broad engine API. Keep native and browser builds working at every runtime milestone. Select exact dependency versions at bootstrap, record them in the build, and build from a clean checkout without global project-specific configuration.

Proposed source layout:

```text
runtime/core/          Timing, input snapshots, resources, diagnostics
runtime/script/        Luau integration and console bindings
runtime/graphics/      Render commands and constrained graphics backends
runtime/audio/         Mixer, voices, streaming buffers
runtime/cartridge/     Index reader, validation, asset delivery
runtime/platform/      Native and browser adapters
tools/                 SDK CLI and import pipeline
sdk/                   API definitions, documentation, project templates
examples/              Reference games
tests/                 Focused conformance and integration scenarios
docs/                  Architecture and project decisions
```

This is an intended layout, not a requirement to create empty module scaffolding immediately.

## Milestone 0: agree on measurable targets

- Record the existing accepted decisions and the unresolved DS/3DS fidelity question.
- Select a minimum native device and browser/device combination, plus a representative browser matrix.
- Define a reference scene and frame-time measurement method. At 60 FPS the full frame has approximately 16.67 ms; allocate script, rendering, and host headroom after measuring the prototype.
- Define distribution, decoded asset, VM heap, GPU, startup-download, and startup-time measurements separately.
- Include PNG wrapper overhead and cover-decoding memory in the measurement definitions, separately from the ROM payload ceiling.

Exit: a short benchmark specification with named test environments, reproducible workloads, and explicit provisional budgets. Do not freeze arbitrary limits based on a development workstation alone.

## Milestone 1: prove both hosts and the VM

- Set up C++20/CMake, pinned Luau, native SDL3 integration, and Emscripten builds.
- Run the same Luau module with initialization/update/render callbacks on both hosts.
- Display a 384 x 216 framebuffer, draw a sprite, map keyboard/controller/pointer input, and play one sample.
- Resolve browser audio delivery, gesture startup, buffering, and the baseline without shared-memory requirements now.
- Implement bounded allocator behavior, source diagnostics, a failing-script path, and an infinite-loop interruption path.
- Add basic native and web build checks to CI.

Exit: clean-checkout instructions produce a standalone native player and a browser build; both run the same source. A script failure or resource limit produces a controlled error, not a frozen player. Audio is measured during an intentional main-thread stall. Record deployment headers and browser requirements explicitly.

## Milestone 2: establish the 2D development loop

- Implement sprites, batching, tilemaps, transforms, clipping, alpha blending, palette swaps, bitmap text, and render targets in the order the reference game needs them.
- Add fixed ticks, input snapshots, seeded randomness, pause/resume, and bounded catch-up.
- Implement an initial manifest, source module resolution, and imported image assets.
- Provide `sdk dev`, `sdk run`, and `sdk check` with API definitions and useful source errors.
- Restart automatically after valid code changes. A failed edit should retain a usable error view and allow recovery on the next save.
- Show frame time, script allocations, resource bytes, draw calls, and asset-loading activity.

Exit: a small scrolling game with animated actors and controller/pointer input runs in both hosts. A new developer can change movement and add a sprite using only the checked-in SDK documentation. Capture measured edit-to-visible latency and compare with the benchmark target.

## Milestone 3: prove occasional 3D and sustained audio

- Add a compact indexed-mesh format, camera/transforms, depth testing, and textured unlit materials.
- Add vertex colors, one simple lighting model, and fog only as the sample requires them.
- Render a rotating textured object into a target composited with the 2D game.
- Expand the mixer to the proposed 16 voices, with documented priority and stealing.
- Select a streaming music codec/decoder after profiling its footprint, decode cost, and licensing. Prove that decoding and asset loading stay off the audio callback.
- Add live asset refresh with safe resource replacement.

Exit: the 2D scene, 3D object, music, and effects run together at the agreed frame target on the minimum device. Report percentile frame times, memory peaks, and audio underruns. Revisit budgets if the prototype fails; do not hide failures by raising only native limits.

## Milestone 4: cartridges, loading, and saves

- Implement the indexed cartridge format, source compilation, version checks, per-entry compression, hashes, and malformed-input limits.
- Specify and implement the PNG wrapper: cover image, private ancillary directory/payload chunks, bounded sizes, and logical-to-file offset mapping. Encode the entire ROM, not a network launcher. Keep the cover viewable in ordinary PNG viewers.
- Implement native open/drop and browser file-picker/drop loading of original PNG cartridges. Read payload ranges without full-ROM extraction or cover-pixel decoding.
- Implement the shared logical asset index with native packed reads and browser chunk delivery.
- Define startup asset sets, prefetch/readiness semantics, cache bounds, cancellation, and loading errors.
- Add isolated native/browser saves with stable identities, schema versions, quotas, and write-error reporting.
- Implement `sdk pack`, `sdk pack --format png`, size reports, and initial web/native exports.

Exit: a representative approximately 128 MB content package starts by fetching its startup set. A synthetic package near the proposed 512 MB ceiling exercises indexing, selective loading, and decoded-memory bounds without full decompression. Test slow/offline delivery, corrupt/truncated entries, oversized decoded assets, unavailable storage, and version incompatibility. Check that saves survive player restart and cartridge rebuild.

PNG acceptance: round-trip both small fixtures and near-ceiling synthetic ROMs through PNG packaging and verify byte-identical logical payloads, stable save identity, and bounded memory. Open the cover in an independent PNG decoder. Load the original PNG on native and web players; confirm a local self-contained cartridge needs no network assets. Reject invalid chunk order/CRC/lengths, excessive cover dimensions, stripped payloads, unsupported versions, and corrupt indexes. Distinguish local bounded reads, remote full-file downloads, optional HTTP ranges, and chunked web exports in startup reports. Document that image resizing/re-encoding can destroy cartridge data.

Synthetic large packages establish container behavior, not the quality or performance of a complete 512 MB game.

## Milestone 5: reference game and automation

- Finish the small playable reference game: scrolling map, animation, effects, music, saves, menu, and a 3D object or scene.
- Add `sdk test` with scripted input, tick limits, state assertions, and structured diagnostics.
- Add graphics-host screenshot checks and offline mixer captures separately from headless logic tests.
- Validate suspend/resume, focus loss, resize, controller reconnect, graphics-context loss, and audio startup/recovery.
- Produce standalone native and static web distributions with required dependencies and license notices.
- Exercise the player-facing PNG open/drop workflow and original-file sharing instructions without requiring the SDK.

Exit: another developer or an AI agent can create a project, diagnose an intentional error, make a gameplay change, run a scenario, and export both targets using the SDK documentation. Native players require no webview, Node.js, compiler, or SDK installation. Browser exports work under the documented deployment contract.

## Milestone 6: prove the API with a second game and freeze v0.1

- Make a second small game with a different 2D workload to identify accidental assumptions in the first game's API.
- Remove or revise awkward APIs while compatibility is still inexpensive.
- Publish the machine profile, memory accounting, feature limits, cartridge version, supported hosts, and compatibility policy.
- Establish conformance fixtures and measured minimum-device performance baselines.
- Confirm whether richer 3D is an evidenced need; keep a 3DS-like expansion separate from completing the initial profile.

Exit: two games use the same documented API without game-specific host escape hatches. Their cartridges run on the native and browser player. v0.1's guarantees are explicit and tested.

## Validation strategy

Use focused tests where a wrong result would violate the machine contract: tick/input behavior, resource ownership and accounting, cartridge parsing, save identity, module resolution, and mixer behavior. Fuzz package/index parsing and critical decoder boundaries when those components exist. Use sanitizers on native builds where supported.

Use integration checks for VM errors/interrupts, real browser startup, selective asset delivery, exported-player dependencies, and save persistence. Test graphical output with tolerances appropriate to documented GPU differences; do not promise pixel-identical output across all drivers. Compare state replays under controlled inputs without claiming universal cross-platform determinism.

PNG tests must verify ROM bytes independently of cover-image validity: a valid-looking image can lack a valid payload. Cover decoding and cartridge reading need separate bounds and malformed-input coverage. Include the PNG wrapper in parser fuzzing once implemented.

Retain compact benchmark reports with exact tool/runtime versions and observed results. A successful compile is not proof of playable performance, and headless tests are not proof of working audio or graphics.

## Main risks and decision gates

| Risk | Resolve by | Required evidence |
| --- | --- | --- |
| Luau/browser integration or bindings cost | Milestones 1-2 | Same module running on both targets, measured script/host-call cost |
| Browser audio glitches or restrictive deployment | Milestone 1 | Stall test, latency/underrun report, documented headers |
| Asset decode/cache memory exceeds nominal budget | Milestones 3-4 | Peak-memory report with temporary allocations included |
| Large packages cause long web startup | Milestone 4 | Network trace showing startup-only fetches |
| Large PNGs trigger full decode or extraction | Milestone 4 | Bounded local-read measurements and separate ROM/cover memory accounting |
| Image processing strips the game payload | Milestones 4-5 | Clear invalid-cartridge errors and original-file sharing instructions |
| Editor tools assume Roblox | Milestone 2 | Correct custom API and module diagnostics in an ordinary project |
| 3D scope overtakes 2D workflow | Milestones 3 and 6 | Reference-game need and explicit scope decision |
| SDK and runtime behavior drift | Milestones 5-6 | Export and conformance checks on native and browser |

No delivery dates are assigned until the first integration milestone reveals platform and tooling costs. The first implementation task is the smallest native-and-browser Luau player with one sprite and one sound, following Milestone 0's measurable target selection.

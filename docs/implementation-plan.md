# Implementation plan

Status: updated 2026-10-19. **Odin is the target language for both games and the runtime**, per [the accepted decision](adr/0001-use-odin-for-games-and-runtime.md). The first native/browser [Odin reproduction](odin-development.md) passes its local sprite/sound and failure checks. The Luau/C++ reference is retained; full profile validation and retirement remain later work. This document supersedes the initial Luau/C++ roadmap.

Keep the standalone native requirement, browser target, single display with 640×360 and 320×180 modes, mostly 2D scope, approximate 128/512 MB package goals, and complete PNG cartridges. The [DS/3DS comparison](target-comparison.md) is advisory; the language change does not expand fidelity scope. The product name remains undecided; use neutral terminology and treat `sdk` command names as placeholders.

## Current evidence

- The Luau/C++ reference player runs on Windows and in Chrome, with a sprite, sound, input, memory/error handling, and matching scripted output.
- The [Odin probe](../experiments/odin/README.md) compiles scalar game-state logic to Windows native code and an identical import-free Wasm module executed in Node and Chrome. It verifies movement, sound-event counts, and one bounds trap.
- The probe does not render, play sound, allocate game data dynamically, load guests in the native player, meter runaway code, or load PNGs.
- The subsequent reproduction does render and play the shared Odin sample on both hosts. Native Wasmtime fuel and browser Worker watchdog/restart paths pass, as do unsupported-ABI, bad-offset, invalid-command, and trap fixtures. A 120-tick replay matches the reference framebuffer hash. See the Odin development guide for exact scope and remaining gaps.
- Existing CI targets the reference player and has not been verified remotely. The [development guide](development.md) documents the reference build.

## Migration approach

Keep the current player runnable while replacing one responsibility at a time. Implement maintained game and runtime code in Odin; use third-party C interfaces for SDL and the selected guest engine. Do not rewrite those dependencies or introduce permanent Luau compatibility as part of this migration.

Proposed boundaries, created only when needed:

```text
runtime/core/          Shared Odin timing, resources, and console behavior
runtime/guest/         Wasm validation, guest ABI, native engine adapter
runtime/graphics/      Odin drawing commands and platform backends
runtime/audio/         Odin sample/mixer behavior and platform output
runtime/cartridge/     Indexed ROM and PNG wrapper readers
runtime/platform/      Native SDL and browser service adapters
sdk/                   Odin API packages, compiler/build orchestration
examples/              Reference game and Odin successor
experiments/odin/      Existing isolated compiler probe
tests/                 Contracts, integration, and conformance
```

The current C++ files are still the reference implementation, not evidence that these Odin boundaries already exist. Keep migration code/build commands distinct until parity is demonstrated, then retire the old implementation in a focused change.

## Milestone 0: define the guest contract and measurement baseline

The prototype ABI and native embedding proof now exist. Selecting minimum devices and a representative performance baseline remains open.

- Define the smallest versioned Wasm ABI: initialization, fixed update, draw submission, input snapshot, one sound request, diagnostics, and state inspection.
- Use fixed-width scalar values and validated offset/length buffers; do not expose Odin context, strings, slices, or native pointers across the ABI.
- Establish context and allocator conventions at every exported Odin entry point.
- Select a native Wasm engine through a small Odin C-interface probe. Wasmtime is a candidate; measure footprint, startup, memory controls, interruption, and deployment dependencies before selecting it.
- Select the minimum native/browser environments and provisional frame, startup, memory, recovery, and iteration targets.

Exit: a documented ABI draft, pinned compiler/dependency revisions, named measurement environments, and a small native engine embedding proof. The prior scalar probe alone does not satisfy this milestone.

## Milestone 1: Odin native and browser player with one sprite and sound

Implemented and checked locally on Windows/Chrome. The identical game module, shared Odin drawing/sample code, input, audio, reference replay, and controlled-failure paths pass. Physical controller/touch devices and clean-machine distribution still require validation.

- Implement an Odin native executable with SDL window/input/presentation/audio integration and embedded guest execution.
- Compile an Odin game to freestanding Wasm. Load the exact same bytes in the native engine and browser Wasm engine.
- Compile the shared Odin runtime for browser execution. Supply only the necessary JavaScript bridge to drawing, input, audio, loading, and storage.
- Run browser game code in a Worker, with bounded command messages and an external watchdog. Keep presentation responsive during runaway code; do not silently require shared memory or cross-origin isolation.
- Recreate the existing example's sprite, movement, bobbing, pointer interaction, action edge, and sound using the shared Odin console behavior.
- Preserve both logical display modes, fixed ticks, bounded catch-up, gesture-unlocked browser audio, pause/resume, and controlled errors.

Exit: a standalone Odin native player and browser player run one identical game module with real graphics/audio. Scripted positions, sound requests, and rendered output match the reference where specified. Native users need no compiler, Node.js, or webview.

## Milestone 2: memory, failures, and developer workflow

- Prove persistent game and per-frame arenas with allocation tracking, exhaustion behavior, and stale-resource diagnostics.
- Validate imports/exports, feature subset, guest memory maximums, command bounds, integer overflow, and resource handles.
- Test traps, stack exhaustion, excessive growth, malformed modules, invalid host requests, and infinite loops on both targets. Native interruption and browser Worker termination must recover cleanly.
- Provide ordinary Odin SDK packages, OLS completion/navigation, compiler diagnostics, and runtime failures mapped to source locations.
- Implement save, compile, validate, restart; retain the last working game on compilation failure. Measure ten warm iterations and three first-run/cold scenarios rather than extrapolating the scalar probe.
- Start with restart-on-change. State-preserving reload requires explicit serialization/version migration.

Exit: useful diagnostics and bounded recovery on both players, measured edit-to-first-frame latency, explicit memory accounting, and no dependence on an unrestricted native game plugin.

## Milestone 3: automate parity and retire the reference implementation

- Add Odin native and browser builds to CI alongside focused contract checks.
- Verify clean-checkout builds and standalone distributions, including required native libraries and license notices.
- Replay the sprite/sound scenario, inspect actual captures, test browser audio through a UI-thread stall, and exercise suspend/resume and focus changes.
- Validate controller/touch support on physical devices and report platform coverage honestly.
- When checks pass, retire Luau, maintained C++ runtime code, and their build dependencies in a focused change. Preserve useful reference fixtures and update build instructions.
- Keep Node/Playwright development utilities where useful; they are not player runtime requirements.

Exit: the supported Odin build replaces the reference player and its documented commands. A compile-only proof or headless state test is insufficient.

## Milestone 4: strong 2D workflow and compact 3D

- Grow sprites, batching, tilemaps, transforms, clipping, palette effects, text, and render targets around the playable reference game.
- Add indexed meshes, depth testing, cameras, vertex colors, simple lighting/fog, and 3D-to-2D composition.
- Develop the proposed 16-voice audio mixer, voice priority, and streamed music after measuring a decoder and proving browser worklet/buffering behavior.
- Add live asset replacement and frame/resource diagnostics.

Exit: the mixed 2D/3D scene and sustained audio meet measured minimum-device targets. Custom shaders, advanced shadows, full physics, and complex animation remain deferred unless game needs justify them.

## Milestone 5: indexed ROMs, full PNG cartridges, loading, and saves

- Package the game module, assets, profile requirements, and optional source/debug data under a versioned manifest.
- Implement native indexed ROM reads, browser chunk delivery, startup sets, prefetch/readiness, cache bounds, cancellation, and corruption handling.
- Implement valid PNG covers plus private ancillary directory/payload chunks carrying the complete ROM. Preserve exact game-module bytes and save identity across wrapper conversions.
- Support native open/drop and browser file-picker/drop without requiring the SDK. Read local payload ranges without full cover decode or ROM extraction.
- Add isolated, failure-aware native/browser saves and explicit byte/memory ceilings.
- Provide provisional `sdk pack`, PNG packing, and native/web exports.

Exit: small and near-512 MB synthetic payloads round-trip with bounded memory. Test malformed PNG/index data, oversized decoded resources, stripped payloads, storage failures, unsupported profiles, and slow/offline delivery. The original-file sharing workflow is documented; image re-encoding is not guaranteed to preserve ROM data.

## Milestone 6: second game and machine profile v0.1

- Complete one playable reference game and a second game with a different 2D workload.
- Use them to refine the SDK and freeze the ABI, cartridge schema, resource limits, and compatibility policy.
- Publish reproducible native/browser conformance, performance, and export checks.
- Revisit richer 3D only with evidence from actual games.

Exit: both games use the same documented Odin SDK and portable guest contract without game-specific host escape hatches.

## Validation and remaining uncertainty

Use focused checks for guest validation, ABI decoding, input/timing, allocation/resource accounting, save identity, mixer output, and parser boundaries. Keep graphics/audio integration checks separate from scalar/headless tests. Fuzz cartridge and guest-command parsers when implemented. Record exact compiler/engine versions and observed results without machine-specific paths.

The embedded Wasm engine, Odin browser host, shared rendering/sample path, and basic Worker recovery are now proven together for this reproduction. Allocation-heavy guest support, source-level debugging, realistic edit-loop timing, broader feature policy, physical input devices, and minimum-device performance remain unproven. These are implementation gates for the chosen language direction, not reasons to treat the whole machine profile as complete.

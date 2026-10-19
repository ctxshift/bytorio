# Odin language evaluation

Historical evaluation: the current [architecture](architecture.md) supports both
Luau and Odin cartridges through one Odin player. The C++ reference player has
been removed; the implementation discussion below records the earlier decision.

Date: 2026-10-19. Status: supporting evaluation; the subsequent [accepted decision](adr/0001-use-odin-for-games-and-runtime.md) selects Odin for both games and runtime.

The working Luau/C++ implementation remains unchanged as a reference. A subsequent [Odin reproduction](odin-development.md) now runs real sprite/sound behavior on native and browser; the scalar probe below remains the original evaluation evidence, not the integration result. This report evaluates the two language roles separately to explain their tradeoffs. The display, mostly 2D scope, standalone native player, browser player, and full PNG cartridge requirement remain fixed.

## Recommendation

The selected direction is **Odin game code compiled to a portable Wasm module, hosted by an Odin player on native and an Odin/browser runtime on web**. That keeps one game binary inside the PNG and preserves a separate player. It adds a native Wasm engine through a foreign interface, a stable binary interface, browser bridging, and new debugging and interruption work.

The user subsequently selected Odin for the runtime as well. Apply the guest ABI and isolation recommendations below to an Odin host through foreign interfaces instead of a maintained C++ core. Keep the reference player functional until the Odin implementation demonstrates an acceptable edit/run loop and equivalent protections. Permanent dual-language game support is not selected.

## What changes for game authors

Odin is a compiled language: its documented `run` command compiles before executing. It provides manual memory management, custom allocators through an implicit context, and bounds checking for arrays/slices that can be disabled. Foreign entry points must establish context explicitly when their bodies require it. These are useful controls, not a memory-safety guarantee. [Language overview](https://odin-lang.org/docs/overview/)

The SDK could hide ordinary allocation behind persistent game arenas and temporary per-frame arenas, while leaving packed arrays and buffers available. Authors would still need to understand lifetimes, stale pointers, ownership, and errors. **Inference:** this suits engine-oriented developers better than the current scripting model; it raises the learning burden for small casual games.

Odin offers array programming, matrices, quaternions, and structure-of-arrays types, but only non-capturing lambda procedures. Game-state callbacks would normally operate on explicit state rather than capture local variables. [Odin FAQ](https://odin-lang.org/docs/faq/)

There is an existing language server, OLS, with completion, definitions, references, rename, signatures, and hover. Its documented editor support includes VS Code. SDK packages should therefore be ordinary Odin source that OLS can inspect. This is evidence of editor tooling, not evidence that AI code generation is as reliable as for Luau or C++. [OLS project](https://github.com/DanielGavin/ols)

## Architecture choices considered

| Choice | Game distribution | Benefits | Main cost | Assessment |
| --- | --- | --- | --- | --- |
| Odin games and Odin host, with portable Wasm guests | One portable guest module plus assets | One primary maintained language, explicit memory, one cartridge executable | Native guest-engine integration, Odin host migration, ABI and browser bridge | Selected direction; integration gates remain |
| Odin games compiled to Wasm; C++ host retained | One portable guest module plus assets | Explicit game memory, one cartridge executable, restricted host imports | Native Wasm engine, binary SDK, browser bridge, tooling | Original guest-only alternative; host decision supersedes it |
| Odin games compiled natively and to Wasm | Per-platform executable/library variants plus web module | Native execution without guest engine | Platform/architecture matrix, unsafe native plugins, incompatible debugging paths | Poor default for a portable fantasy console |
| Odin replaces C++ host; Luau remains | Existing source-based games | Odin for engine development; game ergonomics retained | Host rewrite and Luau C interface wrappers | Separate decision; no demonstrated need |

### 1. Portable Wasm games

Odin's compiler source lists `freestanding_wasm32` and `js_wasm32` targets. The official examples demonstrate JavaScript calling an Odin Wasm procedure. Target availability does not establish that arbitrary desktop packages work unchanged in a custom cartridge environment. [Compiler targets](https://github.com/odin-lang/Odin/blob/master/src/build_settings.cpp), [official browser example](https://pkg.odin-lang.org/examples/wasm/js_wasm32/)

Start with `freestanding_wasm32` and a small import surface owned by the console. Supply the needed allocation and runtime support; inspect generated imports rather than assuming the compiler emits a dependency-free module. `js_wasm32` is useful for ordinary browser applications, but browser-specific runtime dependencies would need adapters on native. Pin a tested compiler version and Wasm feature subset.

Proposed execution paths after the Odin host decision:

```text
native:  Odin player -> embedded Wasm engine -> Odin game.wasm
browser: JS coordinator -> Odin game.wasm
                       -> Odin runtime.wasm
```

Wasmtime supplies embedding examples for C/C++ and memory handling. It is a concrete native-host candidate, not a selected dependency; measure binary size, initialization, supported platforms, and licensing/distribution obligations before choosing it. Native users would install only the player and cartridge, never the Odin compiler. [Wasmtime embedding examples](https://docs.wasmtime.dev/c-api/examples.html)

Both the proposed Odin runtime and game become Wasm on web. A guest module cannot simply call native host addresses. For an initial integration, instantiate it separately and provide JavaScript imports that relay batched commands to exported runtime functions. Keep guest and host memories separate and copy bounded payloads. Sharing memory/linking modules is possible design work, not an automatic consequence of both being Wasm. [WebAssembly JavaScript interface](https://webassembly.github.io/spec/js-api/)

Use numeric handles and scalar arguments for input and resource calls. Use a versioned command buffer for graphics/audio submissions, avoiding a JavaScript transition per pixel or vertex. Freeze integer widths, byte order, structure layout, and error codes; avoid exposing Odin strings, slices, `int`, context, or C++ classes as a public ABI. Reinitialize the required Odin context at exported entry points. This is a proposed interface, not an implemented compatibility guarantee.

### 2. Native games and separate browser artifacts

An Odin game can instead be built as native code for each supported desktop and as Wasm for browsers. A PNG could contain several builds, but it now needs platform selection and grows with the target matrix. Native game libraries in the player's process can access its address space and are not equivalent to isolated guest code. A worker process could add isolation at the cost of IPC and lifecycle machinery.

**Inference:** this is reasonable for trusted, individually exported games; it works against the goal of a universal cartridge loaded by a general-purpose player. The same source is portable only to the extent that its packages, ABI, and platform branches are portable. Native and Wasm builds should not be assumed bit-for-bit deterministic.

### 3. Odin as the runtime language

Keeping Luau while replacing C++ is independent of changing the game language. Odin documents foreign procedures and C calling conventions, so a narrow C wrapper around Luau's C++ implementation is a plausible integration boundary. SDL and graphics bindings would also need validation on both targets. [Foreign interface](https://odin-lang.org/docs/overview/#foreign-system)

The subsequent user decision chooses Odin for both language roles. Migrate the host while preserving the working reference until parity; Luau is not the long-term game-language target. A host rewrite alone would not establish portable cartridge execution, so the Odin Wasm guest ABI and engine integration still require separate validation.

## Memory, runaway code, and errors

Wasm restricts memory access to the guest's accessible memories, but a bad pointer can still corrupt unrelated objects inside its own linear memory. Every host call must independently validate offsets, lengths, overflow, handles, and resource ownership before accessing host data. Keep filesystem/network access absent unless deliberately exposed as capabilities. [Wasm execution properties](https://webassembly.github.io/spec/core/appendix/properties.html), [embedding access model](https://webassembly.github.io/spec/js-api/#security-and-privacy-considerations)

For native hosting, Wasmtime offers store resource limits and execution interruption through fuel or epochs. These are engine facilities, not Odin language features. Fuel and epochs have different overhead and interruption semantics; neither automatically accounts for expensive host calls. [Store limiter](https://docs.wasmtime.dev/c-api/store_8h.html), [interruption guide](https://docs.wasmtime.dev/examples-interrupting-wasm.html)

The browser Wasm API exposes no equivalent fuel/epoch interface. A timer on a blocked main thread cannot stop a synchronous infinite guest loop. A proposed browser design runs the game in a dedicated Worker, with an external watchdog able to terminate and recreate it; that loses execution state and requires a bounded messaging interface. Native fuel counts would not constitute a cross-platform quota. [Wasm JavaScript API](https://webassembly.github.io/spec/js-api/), [Worker termination](https://html.spec.whatwg.org/multipage/workers.html#dom-worker-terminate)

Validate module memories and imports before execution, enforce maximum linear-memory growth, and budget host assets separately. Guest linear memory contains stack, static data, allocator metadata, and heap; its maximum is not identical to the existing Luau heap cap or the proposed resident game-data budget. Browser memory buffers/views must be refreshed appropriately after growth. [Memory API](https://webassembly.github.io/spec/js-api/#memories)

Translate traps, allocation failures, invalid commands, and watchdog termination into useful player diagnostics. Producing source file/line information for compiled Wasm is a separate debugging milestone; do not assume it matches Luau stack traces automatically.

## Edit/run experience and PNG packaging

Proposed loop: save source, compile only the game module, validate it, then replace its instance. Start with restart-on-change. State-preserving hot reload needs explicit state serialization/version migration; copying an old heap into a newly compiled module can retain invalid pointers, layouts, or function references.

Use separate fast development and optimized distribution builds. Measure compiler work, module validation/compilation, instance startup, and first frame separately. Claims of faster execution, smaller cartridges, or faster iteration are hypotheses until measured against representative games; the one-sprite sample is an integration check, not a performance benchmark.

The PNG container requirement stays unchanged: cover art plus the complete payload. A future versioned manifest could identify `luau-source` or `wasm32` execution profiles; that proposal does not authorize implementing permanent dual-language support now. A Wasm cartridge contains code, assets, API/profile requirements, and optional debug/source material. Players reject unsupported versions before execution. Executable code remains separate from streamed assets so a 512 MB package does not need one giant linear-memory allocation.

## Empirical probe

An isolated [compiler/ABI probe](../experiments/odin/README.md) was built and run on Windows using Odin `dev-2026-10-nightly:84bc3fc`, downloaded from the `dev-2026-10` release. It does not modify the current runtime or its demo. The source is [game.odin](../experiments/odin/game.odin); [the verifier](../experiments/odin/verify.mjs) rebuilds and repeats the checks.

| Check | Observed result |
| --- | --- |
| Compilation | The same scalar game-state source compiled to Windows native code and `freestanding_wasm32` |
| Wasm artifact | 4,065 bytes at `-o:minimal`; no imported functions, memories, or tables |
| Execution | The identical module instantiated in Node and Chrome 155.0.8059.41 without browser-specific glue |
| State after 120 updates | x approximately 284, y 100, 120 ticks, two sound events on all three paths |
| Bounds check | Out-of-range array index trapped as WebAssembly.RuntimeError in Node and Chrome |
| Wasm linear memory | 1,114,112 bytes initially, including runtime/stack/static storage; not an allocated game-heap measurement |
| Wasm build wall times | 95, 88, 87 ms across three local rebuilds |
| Native build wall times | 216, 206, 205 ms across three local rebuilds |

These are measurements of a tiny scalar probe, not a cold-cache benchmark, editor-latency measurement, realistic game benchmark, or Luau performance comparison. Native output rounds coordinates for printing; the verifier compares those to Wasm with a numerical tolerance. No general determinism claim follows.

The probe contains no dynamic allocation, host imports, renderer, sound playback, cartridge loader, C++ Wasm engine, or runaway-code controls. Its sound count is an event counter, not an audio test. A bounds trap demonstrates one checked operation, not memory safety. Its 4 KB module size must not be compared to the full existing player as if they implement equivalent features.

The generated `build/odin/report.json` retains local results and is ignored by Git. The public report intentionally omits machine-specific paths. The compiler is a local evaluation tool, not a new required dependency of the accepted player build.

## Bounded proof before any migration

Implement a bounded Odin host/guest slice reproducing the existing one-sprite/one-sound behavior. Leave the working reference intact until the Odin implementation meets its acceptance criteria:

1. One identical `.wasm` payload runs through the standalone native player and browser player, drawing the same sprite and triggering audible sound. No compiler or webview is required by the native user.
2. Input replay produces matching logical positions and sound-event counts over a fixed run; visual/audio output is checked separately. This establishes sample parity, not general determinism.
3. Record ten warm edit/build/restart samples and three cold samples on a named device. Provisional iteration target: warm p95 under two seconds; report optimized-build latency separately.
4. Show completion, jump-to-definition, compiler diagnostics, and at least one runtime failure mapped to the game's source line in the supported editor/browser/native workflow.
5. Test invalid host offsets, length overflow, invalid handles, allocation exhaustion, excessive memory growth, stack exhaustion, and an infinite loop. Each fails with a diagnostic while the player/UI recovers; propose a one-second maximum recovery budget.
6. Report guest linear memory, host resource bytes, total native process memory, browser memory limitations, startup time, module size, and added native engine size. Compare representative entity/buffer workloads before claiming an advantage over Luau.
7. Compile an allocation-using game, not only scalar code. Demonstrate persistent and per-frame arenas with leak/invalid-free diagnostics; Odin provides a tracking allocator that can support this investigation. [Memory package](https://pkg.odin-lang.org/core/mem/)
8. Round-trip the module and assets through the actual PNG cartridge once that subsystem exists. Until then, label PNG compatibility as design compatibility, not a passed test.

Migration acceptance gate: demonstrate acceptable ergonomics and isolation for both targets before retiring the reference implementation. Odin is the chosen direction; failure of an integration check is a reason to resolve or explicitly revisit the affected architectural assumption, not to claim the migration is complete.

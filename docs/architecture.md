# Architecture

Status: initial design, updated 2026-10-19. The first native/browser sprite-and-sound slice is implemented; see [the development guide](development.md). The broader profile and remaining subsystems below are still proposed.

## Product intent and accepted decisions

The project is an independent fantasy console for making and sharing small games. Its development workflow should offer a short creative loop using ordinary source files, modern editors, command-line tools, and AI agents.

The repository codename is temporary; the final product name is undecided. Use neutral terms such as console, runtime, SDK, and cartridge in prose and code comments. Avoid deriving API namespaces, file extensions, package identifiers, or format magic from the codename. Command names below are placeholders, not branding decisions. Keep future user-facing branding in one metadata location rather than scattering name literals through the implementation.

Accepted decisions:

- Game language: Luau, with optional types and a documented console API.
- Runtime implementation: C++, shared between native and browser targets.
- Native execution: a standalone runtime without a webview; playing games must not require Node.js or a developer toolchain.
- Browser execution: compile the runtime to WebAssembly; use JavaScript only where browser integration requires it.
- Display: one 384 x 216 logical screen.
- Content emphasis: mostly 2D, with occasional 3D.
- Distribution: approximately 128 MB typical game size, approximately 512 MB maximum.
- Distribution includes a self-contained ROM encoded in a PNG cartridge, with visible cover art, loadable by both native and browser players.

The system does not emulate Nintendo hardware or run Nintendo game binaries. DS-era games are the original production-quality reference. Whether to raise that reference to 3DS-level fidelity remains open; see [the comparison](target-comparison.md). Do not silently change the accepted display or content emphasis as part of that discussion.

## Proposed machine profile

Everything in this section beyond the accepted display and package-size intent is provisional until the reference game and minimum-device measurements justify freezing it.

| Area | Initial proposal |
| --- | --- |
| Simulation | Fixed 60 Hz ticks |
| Presentation | 60 FPS target; explicit 30 FPS rendering option |
| Display | 384 x 216, nearest-neighbor presentation, integer scaling and letterboxing |
| Colors | RGBA rendering with optional palette-indexed assets and palette swaps |
| 2D | Sprites, tilemaps, transforms, clipping, blending, text, render targets |
| 3D | Textured meshes, depth testing, vertex colors, basic lighting and fog |
| Audio | 16 logical mixing voices, stereo, samples and streamed music |
| Input | D-pad, four face buttons, shoulders, start/select, pointer/touch |
| Resident game data | 64 MiB initial budget hypothesis |
| GPU resources | Separate accounting; limit to be measured |
| Storage | Read-only cartridge plus isolated persistent saves |
| Shareable format | PNG image containing the full cartridge payload |
| Initial hosts | Windows native and browser; macOS/Linux compatibility designed in |

Use decimal MB for distribution targets and binary MiB for memory. Before freezing the cartridge format, confirm whether the nominal 512 MB ceiling means 512,000,000 bytes or 512 MiB; the reader must enforce an explicit byte ceiling.

Resident game data includes script heap, buffers, decoded CPU assets, mesh data, and resident audio. Report VM/compiler overhead, temporary decoding peaks, package cache, GPU allocations, and total process/Wasm memory separately. Logical resource accounting is not a guarantee about browser process memory. Retain a VM heap cap within the resident budget so script tables cannot consume the whole asset allowance unexpectedly.

Do not invent a virtual CPU frequency. Start with performance measurements and runaway-script protection. A portable, deterministic CPU quota would require a separately designed meter, including charges for expensive host calls.

## Runtime boundaries

```text
Luau game source + cartridge assets
                  |
       Luau VM and console API
                  |
  timing / resources / graphics / audio / saves
                  |
      narrow platform service interfaces
           /                     \
 native host                 browser host
 SDL3 + desktop GL           Wasm + WebGL 2
 native files/audio          fetch/storage/audio glue
```

The shared core owns observable game behavior. The host owns delivery to physical devices and platform services. Game code never calls SDL, OpenGL, browser globals, native filesystem APIs, or arbitrary host libraries directly.

Suggested implementation choices, subject to the first integration milestone:

- C++20 and CMake, with pinned Luau and other dependency revisions.
- SDL3 for native windows, input, controller mapping, and audio-device integration. SDL supports these services and works with C++: [SDL3 documentation](https://wiki.libsdl.org/SDL3/FrontPage).
- Desktop OpenGL 3.3 and WebGL 2 backends sharing a constrained renderer and shader templates. Avoid desktop-only features. Emscripten recommends the WebGL-friendly OpenGL ES subset: [graphics documentation](https://emscripten.org/docs/porting/multimedia_and_graphics/OpenGL-support.html).
- TypeScript for SDK orchestration, development server, import tooling, and editor integration where useful. It is a development dependency, not a native player dependency.

Keep interfaces specific: input snapshot, asset read request/completion, save read/write, drawing submission, audio delivery, monotonic host time, and diagnostics. Avoid a generic plugin framework before a concrete need exists.

## Game execution and language services

One Luau VM per running game. Compile source using the compiler revision bundled with that runtime. Start without native Luau code generation so browser behavior and the baseline execution path remain comparable; native acceleration can be evaluated later.

Expose initialization, fixed update, and render callbacks through a returned game module. Exact names and signatures are to be proven by the reference game. Keep mutable game state explicit so restart, serialization, and future reload hooks have understandable boundaries.

Use a small set of API namespaces, initially graphics, input, audio, assets, storage, math, and diagnostics. API names are proposals until implemented. Provide packed buffers and bulk operations for procedural assets and large data sets; ordinary gameplay should not require manual allocation or pointer arithmetic. Luau already provides bounds-checked byte buffers: [standard library](https://luau.org/library/).

Ship API type definitions and documentation from one maintained source. Configure luau-lsp for this custom environment, without Roblox globals, and resolve modules consistently in the compiler, language server, and runtime. The language server supports custom definitions: [luau-lsp](https://github.com/JohnnyMorganz/luau-lsp).

Initial editing behavior is automatic restart after valid source changes. Preserve saves. Add live asset replacement next. State-preserving code reload requires explicit export/import hooks; arbitrary closures and VM internals are not a reload contract.

## Timing and reproducibility

Sample input into a per-tick snapshot. Use an accumulator for fixed updates, cap catch-up work, and define pause/resume behavior for background tabs and suspended native windows. Never let a long suspension create unbounded simulation catch-up.

Provide a seeded PRNG and virtual tick time. Record input by tick for regression tests. Wall-clock time, asynchronous asset completions, floating-point behavior, and GPU output can introduce differences: fixed ticks alone do not promise cross-platform deterministic replay or rollback networking.

## Graphics

Render into the logical framebuffer, then present it using a documented scaling policy. Pointer coordinates map back into that logical space, with an explicit policy for letterboxed areas.

Make 2D the primary API: sprite batching, indexed and RGBA textures, tilemaps, camera transforms, clipping, palette effects, text, and offscreen targets. Specify blend semantics and ordering; batch only where visual order remains correct. Document straight versus premultiplied alpha and color-space behavior before importer output becomes stable.

Implement 3D as a small mesh API with cameras and transforms. Supply unlit/textured and simple lit materials, depth testing, vertex color, transparency policy, fog, and nearest filtering. Render 3D to targets that compose with sprites and UI. Select a small import subset and perform expensive conversion offline.

Custom game shaders, advanced shadows, PBR, general scene editing, full physics, and complex skeletal animation are deferred. Resource handles must detect stale use, and large GPU resources need explicit release plus cleanup at game shutdown. Keep enough asset provenance to recover from browser graphics-context loss.

## Audio

Share the mixer, voice rules, and sample interpretation between hosts. Start with 16 voices including music voices; define voice stealing and priority. Use a stable internal sample rate with host conversion as required. Add compressed music streaming only after selecting and profiling a decoder. Do not expand whole music tracks into PCM at startup.

Audio callbacks must not allocate, fetch files, compile scripts, or wait for game execution. Browser audio must survive brief main-thread stalls and require the appropriate user gesture to begin. The initial slice plays the shared C++ PCM sample with a browser AudioBufferSourceNode and an SDL native audio callback. This proves static sample playback independently of the UI thread; it does not yet implement the full mixer. Before sustained/streaming audio, select and prove an AudioWorklet delivery approach, buffer ownership, latency, and underrun behavior. A baseline deployment must not require SharedArrayBuffer or cross-origin isolation; if that baseline fails the audio requirements, explicitly revisit the deployment contract rather than adding the requirement silently.

## Assets and cartridge format

Development projects are ordinary folders containing a manifest, Luau source, and source assets. Importers produce reproducible runtime assets in a generated directory. Keep generated caches out of source control unless a particular release workflow requires them.

The packed cartridge has a versioned manifest/index, bounded offsets and lengths, independently compressed entries or chunks, stable identifiers, and integrity hashes. Hashes detect corruption; they do not establish publisher trust. Reject traversal paths, overlapping/invalid ranges, oversized decoded entries, unsupported versions, and decompression bombs before allocating large buffers.

Initially ship source and compile it with the local trusted compiler. Luau assumes valid compiler-produced bytecode; arbitrary downloaded bytecode is not a safe interchange format: [Luau sandbox guidance](https://luau.org/sandbox/).

Use the same logical asset index across delivery modes:

- Native: indexed reads from a packed local cartridge.
- Web: exported fetchable chunks by default; optional HTTP range delivery later.
- Development: source directory and importer cache.

PNG packaging is another representation of the same logical cartridge. It must preserve source, assets, identity, and machine-version requirements rather than define a second game format.

Define a small startup asset set. Prefetch levels explicitly and deliver asset readiness through controlled update-boundary events; the browser runtime must not pretend arbitrary network reads are synchronous. Bound cache growth and loading concurrency. Measure compressed bytes, decoded bytes, temporary memory, and startup downloads independently.

### PNG cartridges

Accepted requirement: a single valid PNG containing a viewable cover and the complete game ROM. Opening the image displays its cover; opening or dropping the original file into a player loads the game. A cover containing only a URL or requiring external game assets does not satisfy this requirement. The container format and limits are defined independently in this project's specification.

Proposed encoding, to prove before freezing the format:

- Use normal PNG image data for modest-sized cover art and private ancillary chunks for the indexed ROM payload. PNG defines private and ancillary chunk conventions: [PNG specification](https://www.w3.org/TR/png-3/#5ChunkNamingConventions).
- Include an early versioned cartridge directory and a bounded sequence of payload chunks before IEND, respecting PNG ordering rules. Define exact chunk names, copy-safety flags, sizes, and ordering during the format milestone; do not bake the temporary codename into them.
- Keep payload entries independently compressed, with logical offsets mapped to physical file ranges. Preserve efficient reads without decoding cover pixels or inflating the entire ROM. Do not encode a large ROM as a gigantic pixel array or base64 text by default.
- Keep payload, PNG container overhead, cover-decoding memory, and decoded asset budgets separate. The approximate 128/512 MB intent applies to ROM payload; specify an additional bounded wrapper allowance before freezing exact distribution byte limits. A PNG wrapper does not make the ROM materially smaller.
- Read original bytes with the cartridge parser, not a canvas pixel round-trip or a generic image-decoder metadata API. Validate signature, chunk order, lengths, CRCs, directory mappings, payload hashes, image dimensions, and both encoded/decoded size limits before expensive work.
- Use bounded file reads for local PNGs on both hosts. An unoptimized remote PNG requires downloading the file; optional HTTP range support can preserve selective loading where the server permits it. Static web exports retain chunked delivery so fast startup does not depend on range support.
- Repacking or converting between the packed ROM and PNG wrapper must preserve cartridge identity and logical contents. No persistent copy of the entire extracted ROM should be necessary to play a local PNG.

The original PNG file is the distribution artifact. Image editors, screenshotting, social-platform processing, or image optimization may remove private chunks; visual equivalence is not ROM preservation. Document an original-file download/share workflow, detect missing or corrupt payloads, and provide a clear error. Survival through arbitrary image re-encoding is not promised. Pixel-based data encoding is not part of the initial proposal; revisit it only if preserving payload through specific image transformations becomes a requirement.

## Saves and isolation

Namespace saves by stable cartridge identity, separate from the cartridge and development source. Use versioned save schemas, bounded writes, and failure-aware commit semantics. Native and browser persistence have different failure modes; report quota, unavailable storage, and failed writes to the game. Asset hashes should not change save identity on each build.

Sandbox Luau libraries and custom host bindings, impose allocator limits, and implement interrupt checks for runaway scripts. Luau interrupt hooks are not a deterministic instruction budget, and long host functions also need bounded work. The VM sandbox is one layer; native parsers, decoders, compiler input, and bindings still need validation and memory-safety checks. See [Luau embedding guidance](https://luau.org/sandbox/).

Default game capabilities are graphics, audio, input, cartridge reads, and saves. Network access and host filesystem access require a later capability design. Development tools may access the chosen project directory; that permission does not extend to a distributed game.

## SDK and automation

Proposed commands, not currently implemented:

| Command | Intended behavior |
| --- | --- |
| `sdk new` | Create a small ordinary-files project |
| `sdk dev` | Watch, import, check, restart, and serve browser preview |
| `sdk run` | Launch the standalone native host from a source project, packed ROM, or PNG cartridge |
| `sdk check` | Validate manifest, types, source, and assets without running |
| `sdk test` | Execute headless scripted scenarios with bounded ticks |
| `sdk pack` | Create a validated packed ROM and size report |
| `sdk pack --format png` | Encode the complete ROM and cover art as one PNG cartridge |
| `sdk export web` | Emit a static browser player and asset chunks |
| `sdk export native` | Bundle the standalone player, cartridge, and required runtime libraries |

`sdk` is a neutral executable placeholder. The player must support opening/dropping a PNG cartridge directly; using the SDK is not a requirement for players.

Provide readable errors plus structured diagnostics with source paths, lines, severity, and stable codes. Return meaningful exit codes. Support deterministic test inputs, tick limits, state assertions, screenshots through a graphics-capable test host, and offline audio captures. Headless state tests alone do not validate rendering or browser audio.

## Compatibility and deferred decisions

Version machine profiles, cartridge schema, SDK, and runtime separately. A cartridge declares the machine/API version it needs. Reject unsupported required features clearly. Compatible native and browser players must expose the same promised profile; richer native hardware is not permission for games to depend on extra capabilities.

Before v0.1 freezes, settle minimum devices/browsers, total memory envelopes, CPU/GPU limits, audio decoder/output behavior, save limits, asset formats, and exact package byte limits. Version any later expanded graphics profile explicitly. A second profile is deferred until games demonstrate a need.

Deferred work includes alternative cartridge languages, Wasm guest modules, a new programming language, networking, rollback, storefronts, a fantasy desktop, and a full asset editor suite.

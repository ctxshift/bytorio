# Compiled executor caching

The cache stores **code**, never a running game, VM heap, or save state. Each cartridge still gets a fresh Wasm instance. Its Luau source is compiled and its resources are uploaded on load. The frame and sound traces, plus initial tick/sound checks, guard against state leaking across cached instances.

## Native

The Odin player enables Wasmtime's persistent compilation cache for source-based cartridges. By default it generates `executor-cache.toml` and an `executor-cache/` directory beside the development player. No cache files are put in cartridges or copied into staged builds. Wasmtime keys artifacts using module and engine configuration; changing code, Wasmtime/compiler configuration, or metering cannot silently reuse the wrong artifact. [Wasmtime cache API](https://docs.wasmtime.dev/c-api/config_8h.html), [cache configuration](https://docs.wasmtime.dev/cli-cache.html).

`--executor-cache file.toml` selects an explicit Wasmtime cache configuration; its `[cache].directory` must be an absolute path. `--no-executor-cache` disables caching. The default location suits this writable development build; an installed player can select an application cache directory instead.

The benchmark creates a fresh cache directory for each cold case, then launches a second process against the same directory. It checks Wasmtime's pinned-version cache metadata (`usages >= 2`) to confirm reuse. Cache configuration stays enabled in both cases, so a cold cache miss includes cache population work. The existing `compileMs` metric now means **compile or load compiled module**, including validation/decompression. Metered and unmetered variants are measured separately. A different module returning an incompatible ABI is also rejected when using an already populated executor cache.

## Browser

`executor-cache.js` owns a page-session cache of compiled `WebAssembly.Module` objects. A module is shared with each dedicated game Worker through structured cloning, while linear memory remains private to the fresh instance. The cache holds at most four versions and also retains their validated Wasm bytes for the guest policy checks.

Staging writes `executor-version.json` containing the executor's SHA-256. Each load checks this small manifest. On a hit it reuses the compiled module and bytes without downloading the executor again; on a miss it downloads the module, verifies its hash, compiles it asynchronously, and caches the result. A changed manifest selects a new cache key. A manifest/module mismatch fails with a reload diagnostic instead of using stale code. Concurrent requests for the same module share the compilation promise.

This is a **player-page lifetime cache**, not persistent storage across browser restarts or full page navigation. IndexedDB refused compiled modules in the tested Chrome version; a SharedWorker module transfer also failed across its agent cluster. Neither unsupported path is shipped. Dedicated game Workers successfully receive the module from their owning page. The browser's own lower-level compilation cache may additionally help cold loads, but is outside our control.

The cached benchmark explicitly primes the page cache before measuring fresh game Workers, verifies hits and no repeat executor downloads, and checks new module bytes invalidate the key. The cold control bypasses this application cache, not the browser engine's internal caches. A full application shell can keep the page cache alive while switching cartridges; the current standalone player retains it for reload/restart operations within the same page.

The cache retains the approximately 694 KiB executor bytes plus compiled code outside guest linear memory. Engine code residency and total browser process RAM were not measured. Nothing in this cache removes the need to compile Luau cartridge source or allocate a fresh VM heap.

Run `node experiments/luau-executor/verify-cache.mjs` after building to check compiled object reuse, no-download hits, version changes, and manifest/hash mismatches. The benchmark verifies native artifact reuse, fresh instance state, and complete quest/defeat parity.

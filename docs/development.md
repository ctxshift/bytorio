# Building and running the first slice

This guide describes the existing **Luau/C++ reference slice**. The target architecture has moved to [Odin for games and runtime](adr/0001-use-odin-for-games-and-runtime.md); the Odin player migration is planned in [the implementation plan](implementation-plan.md). The commands below continue to build the working reference player.

This slice runs `examples/hello/main.luau` in a shared C++/Luau core on native desktop and WebAssembly. It draws one built-in 16 x 16 sprite into a 384 x 216 framebuffer and plays one generated PCM sample. The small procedural assets keep the first integration independent of an unfinished importer or cartridge format.

## Prerequisites

- CMake 3.24 or newer, Git, and a C++20 compiler. On Windows, install the Visual Studio C++ desktop workload and a Windows SDK. The local build was developed with Visual Studio 2026.
- Emscripten **6.0.12** and Ninja for the web target.
- Node.js 20 or newer for the development HTTP server and browser verification only. Native players do not use Node.js or a webview.

CMake fetches Luau **0.743** and SDL **3.4.18** at exact commit hashes. Initial configuration needs network access. Dependency source, build output, and local SDK installations are ignored by Git.

Commands below run from the repository root. Names are generic implementation targets, not a final product name.

## Native

In PowerShell:

```powershell
./tools/build.ps1 native
./build/native/Release/player.exe
```

If CMake selects an unsuitable generator, specify one explicitly, for example `-NativeGenerator 'Visual Studio 18 2026'`. Changing generators requires a separate build directory or a clean reconfiguration.

On other hosts, the equivalent CMake flow is:

```sh
cmake -S . -B build/native -DCMAKE_BUILD_TYPE=Release
cmake --build build/native --config Release --target player core_tests -j 8
```

Single-configuration generators put `player` directly in `build/native`; Visual Studio puts it in `build/native/Release`. Windows is the first validated native target; Linux/macOS portability still requires live validation.

The native executable loads `game/main.luau` beside the executable, independently of the working directory. The build copies the example there. Distribute that directory and the generated `licenses` directory with the executable. On Windows, SDL and the C/C++ runtime are statically linked. To run an edited source file directly:

```powershell
./build/native/Release/player.exe --script examples/hello/main.luau
```

Use arrows or WASD to move, Space or the controller's south button for sound, and click/touch to position the sprite and trigger sound. Controller D-pad movement and hotplug are wired but need physical-device validation. Focus loss pauses updates; long stalls have bounded catch-up. This is a source-file player, not a packed-ROM or PNG loader yet.

## Browser

Use an installed, activated SDK through `EMSDK`, or keep one local to this checkout:

```powershell
git clone https://github.com/emscripten-core/emsdk.git .tools/emsdk
./.tools/emsdk/emsdk.bat install 6.0.12
./.tools/emsdk/emsdk.bat activate 6.0.12
./tools/build.ps1 web
npm run serve
```

Open [the local player](http://127.0.0.1:8080/player.html) and click **Start game** to unlock audio. The web build embeds the exact same example source at `/game/main.luau`; rebuild after editing it. Serve over HTTP on localhost, or HTTPS when hosted. No SharedArrayBuffer, COOP/COEP headers, or cross-origin isolation is required.

Host `player.html`, `player.js`, `player.wasm`, `player.data`, and the generated `licenses` directory together. Use `application/wasm` for Wasm files. The included Node server serves only on loopback and is a development convenience, not a production hosting service. `npm install` is only needed for browser tests; serving uses Node built-ins.

The initial renderer uploads a shared software framebuffer through SDL's renderer; it is not the planned sprite-batching/mesh renderer. Browser sound uses an AudioBufferSourceNode containing a copy of the shared C++ sample. This single sample plays on the browser audio graph during UI-thread stalls. It does not establish streaming-mixer or AudioWorklet readiness; that integration remains ahead of sustained audio work.

## Verification

Core contract tests cover the actual example, input changing sprite output, sound-trigger consumption, non-silent PCM, source errors, callback errors, runaway top-level execution, non-finite coordinates, and allocator limits:

```powershell
ctest --test-dir build/native -C Release --output-on-failure
```

The native smoke mode runs 120 fixed updates with scripted movement and a second sound trigger, writes a JSON report, and exits. It exercises a real SDL window, renderer, and audio device. An optional capture saves the logical framebuffer:

```powershell
New-Item -ItemType Directory -Force build/verification | Out-Null
./build/native/Release/player.exe --smoke --capture build/verification/native.bmp |
    Set-Content -Encoding utf8 build/verification/native.json
```

Browser verification uses Playwright. Install its pinned development dependency and a test browser, then run:

```powershell
npm ci
npx playwright install chromium
$env:PLAYER_NATIVE_REPORT = 'build/verification/native.json'
npm run test:web
```

To use an already installed Chrome instead of downloading Chromium, set `PLAYER_BROWSER_CHANNEL=chrome`. The verifier starts and stops its own loopback server. It checks loading, keyboard movement, gesture-unlocked sound, non-silent offline audio output, audio-clock progression during a 500 ms main-thread stall, and a matching native/Wasm scripted framebuffer when a native report is supplied. It also substitutes five source fixtures through the real browser loader to verify syntax, module and callback errors, infinite-loop interruption, heap exhaustion, and visible error messages. It saves `build/verification/browser.png`.

These tests establish sample data and output-path behavior; automated browser audio tests do not prove a human heard sound on a physical speaker. Likewise, a framebuffer hash match for this example is not a cross-platform deterministic rendering guarantee.

## Prototype API and limits

A module returns `init()`, `update(dt)`, and `draw()` functions. `dt` is always 1/60. It can call:

- `console.clear(r, g, b)` with 0-255 channels.
- `console.sprite(x, y)` for the built-in sprite, with clipping.
- `console.button(name)` for `left`, `right`, `up`, `down`, or `action`.
- `console.pointer()` returning pressed, x, and y in logical coordinates.
- `console.sound()` to request the built-in sample. Repeated requests within one presentation coalesce.

These are provisional API bindings. They do not create codename-derived public namespaces. Game globals and built-in libraries are sandboxed; the host supplies no filesystem or network bindings.

The script heap is capped at 8 MiB, source files at 256 KiB, and each module/callback at approximately 100 ms using Luau interrupt checks. This is runaway protection, not a portable CPU quota or the final machine budget. Compiler allocations and runtime host allocations are outside the VM heap cap. Source errors are displayed in browser status or native stderr/window title, with a failing process exit code on native.

# Development

The console player and renderer are Odin on native and browser hosts. Luau and
Odin cartridges share that player. The original C++ reference player and its
root CMake build have been removed; historical implementations remain in Git.

## Prerequisites

Use Node.js 24, PowerShell 7, and the pinned Odin/SDL/Wasmtime toolchain described
in [Odin development](odin-development.md). The SDK CLI currently targets Windows
x64 development. Players need neither a compiler nor Node.js to run.

Luau support additionally requires CMake 3.24+, Ninja, Emscripten 6.0.12, and a
native C++ compiler for the analyzer (on Windows, the Visual Studio C++ desktop
workload and Windows SDK). Emscripten builds the C++ Luau compiler/VM and its
adapter into `luau-executor.wasm`; the Odin player runs this same module on both
hosts. `tools/build-luau-tools.ps1` builds the development analyzer. Both use
pinned Luau sources under `build/luau-executor/_deps/luau-src`, independently of
any old player build directory.

## Build and run

From the repository root:

```powershell
npm ci
./tools/build-odin.ps1 all -Fixtures
npm run serve
```

Open `http://127.0.0.1:8080/player.html` and click **Start game**. Native:
`./build/odin-player/native/player.exe`.

For new Luau or Odin games, use [the SDK CLI](../sdk/README.md). For matching
native/browser examples in both languages:

```powershell
npm run build:rpg
npm run serve:rpg
# Open http://127.0.0.1:8080/comparison.html

npm run build:racing
npm run serve:racing
```

See the [RPG guide](rpg-comparison.md) and [racing guide](racing-demo.md) for
controls, standalone launch commands, and cartridge sources. `build:unified`
and `serve:unified` remain aliases for the shared RPG setup.

## Checks

```powershell
npm run lint
npm run format:check
npm run test:odin
npm run test:sdk
npm run test:display
npm run test:rpg
npm run test:racing
```

Build the corresponding examples first. Browser checks use Playwright Chromium,
or installed Chrome with `PLAYER_BROWSER_CHANNEL=chrome`. `test:display` needs
the RPG build. `test:rpg` runs the shared-player integration harness with one
sample per variant, checking quest/defeat replays, native/browser parity, audio,
diagnostics, and executor cache behavior. `bench:unified` uses the same harness
with multiple samples for performance measurement. Old C++-specific CTest and
`test:web` commands no longer exist.

JavaScript and inline HTML scripts use ESLint and Prettier. Use `npm run format`
and `npm run lint:fix` while editing; CI enforces the checks above. Project scripts
use Node.js and PowerShell, with no separate Python project tooling.

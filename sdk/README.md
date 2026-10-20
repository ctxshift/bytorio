# Console SDK 0.2.0

Both players support three [frame-rate policies](../docs/frame-pacing.md):
a custom render cap (60 FPS by default), uncapped rendering, and native display
refresh. Simulation remains fixed at 60 Hz in both SDKs.

Two authoring SDKs for the same **resource-av-1** console. Luau is the default
authoring language; Odin is supported for explicit memory control and performance.
The standalone native and browser players share the Odin renderer and cartridge
ABI. The [formal specification](../docs/cartridge-spec.md) defines behavior and
[contract.json](contract.json) records wire constants and required exports.

The [typed graphics/audio specification](../docs/resource-av-spec.md) and
[published profile](profiles/resource-av-1.json) define SDK 0.2.0 / ABI 2.
[Resources](resources.md), [explicit graphics](graphics.md), [PCM audio](audio.md)
and [synthesis/effects](synthesis.md) work through both SDKs on native and browser.
SDK 0.1.0 / ABI 1 remains an explicit compatibility profile. Existing manifests
retain their version; new projects request SDK 0.2.0 and `resource-av-1`.
See [profile negotiation and conformance](../docs/resource-profile.md).

SDK 0.3.0 / `compact-3d-preview-1` is an explicit experimental opt-in for
[meshes, cameras, depth and voxel resources](../docs/compact-3d.md) in both SDKs.
Create ordinary SDK projects, then set that SDK/profile tuple in `console.json`.
`mise run build:3d` exports the matching native/browser prototypes.

## Start a game

Run from the SDK repository root:

```text
mise install
mise exec -- npm ci
mise exec -- npm run console -- new my-game
mise exec -- npm run console -- check my-game
mise exec -- npm run console -- run my-game --web
```

For Odin, create with `new my-game --language odin`. Projects are ordinary folders;
they may live outside this repository. The `new` command refuses existing folders.
The CLI currently supports **Windows x64** native development and browser builds
from Windows, using the repository's pinned Odin, Wasmtime and Emscripten toolchains.
See [toolchain setup](../docs/odin-development.md); Luau executor builds additionally
require the [Luau CMake/C++ setup](../docs/development.md). Odin-only SDK projects
do not build the Luau executor. For Luau projects, `check` uses the prebuilt Luau
analyzer installed by mise, matching the executor's pinned Luau version. Preparing
a fresh toolchain requires network access; subsequent builds reuse it.

New Luau projects include VS Code settings for the standard Luau platform and the
new type solver, matching command-line checks. The SDK's `read` table properties
require that solver. For an existing project, merge the settings from
[the editor template](templates/luau-settings.json). If diagnostics remain after
the settings load, run **Luau: Reload Language Server** in the command palette.

| Command                                                    | Behavior                                                     |
| ---------------------------------------------------------- | ------------------------------------------------------------ |
| `new <directory> [--language luau\|odin]`                  | Create source, manifest, art and editor configuration        |
| `check <directory>`                                        | Check types, assets, ABI and first rendered frames           |
| `build <directory>`                                        | Check and stage standalone native/browser player folders     |
| `pack <directory> [--output game.png] [--cover cover.png]` | Build and export a viewable PNG containing the complete game |
| `run <directory> --web [--port 8080]`                      | Build and serve the browser player on localhost              |
| `run <directory> --native`                                 | Build and launch the native player                           |
| `watch <directory> --web`                                  | Rebuild after edits; reload the browser to reset the game    |
| `watch <directory> --native`                               | Rebuild and restart the native player after edits            |

`build/native` contains the executable, libraries, licenses and cartridge files.
Copy that whole folder to run without Node.js, a compiler or a webview. Both
languages launch with `player.exe`, loading `game.png` automatically. Share the
single `build/game.png` file with another compatible player. `build/web` can be
served as static files; its configured player loads the same PNG. The browser
also accepts local PNGs through **Open cartridge** or drag-and-drop. See
[PNG cartridges](../docs/png-cartridges.md) for the format, custom artwork,
runtime components, loading commands and current preview limits.

## Project structure and lifecycle

`console.json` declares SDK version, title, language, entry path, asset path, optional PNG cover path and
initial display. Supported displays are `[640,360]` and `[320,180]`. Paths are
relative to the project and may not escape it. `assets.json` contains exactly
16 `#RRGGBB` palette entries, 1..256 sprites of sixteen 16-character rows, and an
optional ASCII bitmap font. Sprite pixels are palette digits `0`..`f` or `.` for
transparency. Font entries have seven five-bit string rows. Extra source metadata,
such as a tile map, can be stored in this JSON and in normal game modules.

Luau's entry is a `.luau` module returning `init`, `update(dt)` and `draw` functions.
Use `local console = require("@console")`. Strict types and completions come from
the real SDK module copied into ignored `.console/`, with a portable `.luaurc`
alias. The CLI analyzes game sources and their dependencies, then bundles literal
relative `require("./module")` and `require("@console")` calls. Modules execute
once and cache their returned value. Cycles, dynamic requires, shadowing `require`,
external packages and paths escaping the project are unsupported. Strings and
comments are preserved. The player requires no filesystem module loader.

Odin's entry is a package directory with `package main`, `init :: proc()`,
`update :: proc(dt:f64)` and `draw :: proc()`. Import `console "sdk:console"`.
The CLI supplies the collection, generates an atlas package and lifecycle entry
point under `build/generated/`, and compiles the cartridge. Source names
`console_entry.odin` and the `console_assets/` package are reserved. The generated
atlas can be imported as `assets "./console_assets"` from the entry package.
Game authors do not write Wasm exports or buffer-offset code.

Both SDKs initialize input/time/random state, prepare graphics batches and provide
the same console operations. Update always receives 1/60 seconds; input edges
are sampled once per tick. Keep simulation in update and presentation in draw.
Changing display mode does not reset state. Calling your own init callback to
restart a round does not reload the SDK. See [the API reference](api.md).

Odin retains normal explicit memory management: allocations belong to the game,
and temporary allocations need an explicit reset strategy. The SDK itself uses
fixed buffers for frame drawing and diagnostics. Avoid returning strings backed
by dead stack storage, or allocating text every frame without reclaiming it.

## Direction and camera input

The original `left`, `right`, `up`, `down`, and `action` buttons retain their
bindings and bits. `buttons()` still returns only those five bits. The current
player also delivers independent `move_left/right/up/down` (WASD or gamepad
D-pad), `pan_left/right/up/down` (arrows), `rotate_left/right` (Q/E), and `reset`
(R). Odin uses `MoveLeft`, `PanLeft`, `RotateLeft`, and the corresponding enum
members; Luau uses the lowercase names with underscores. `button`, `pressed`
and `released` support every named button. `all_buttons()` returns the complete
mask. These optional controls require the current player; older SDKs continue
to ignore the extra bits. See the canonical values in `contract.json`.

## Verify

```text
npm run test:sdk
npm run test:cartridge
```

The suite builds real projects with both SDKs and verifies native/browser parity,
mode switching, clipped and sized sprites, text, input edges, pointer delivery,
known random vectors, sound events, reload, static errors and invalid arguments.
Retained projects and outputs live in ignored `build/sdk-verification/`.
The RPG and racing examples also use these SDKs; their existing build commands
generate the entry points and pack their shared art. Racing replays retain all
2,236 pre-SDK framebuffer/sound pairs, and RPG checks retain the original artwork
hashes within its historical 384×216 scene on the current default canvas.

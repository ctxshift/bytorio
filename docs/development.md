# Development

The console player and renderer are Odin on native and browser hosts. Luau and
Odin cartridges share that player. The original C++ reference player and its
root CMake build have been removed; historical implementations remain in Git.

## Prerequisites

Use [mise](https://mise.jdx.dev/) 2026.10.15 or newer and the pinned toolchain in
`mise.toml`, also described in [Odin development](odin-development.md). The SDK CLI currently targets Windows
x64 development. Players need neither a compiler nor Node.js to run.

Mise installs Node.js, Odin (including SDL), the Wasmtime C API, odinfmt from OLS,
StyLua, and the prebuilt Luau analyzer. It also installs CMake, Ninja and
Emscripten 6.0.12. Native builds require the Windows linker prerequisites from
Odin's installation guide. Emscripten builds the C++ Luau compiler/VM and its
adapter into `luau-executor.wasm`; the Odin player runs this same module on both
hosts. The executor uses pinned Luau sources under
`build/luau-executor/_deps/luau-src`; the analyzer matches Luau 0.743.
The upstream Emscripten SDK installer needs Python, which mise supplies; no
project scripts are written in Python or require its packages.

## Build and run

From the repository root:

```sh
mise install
mise exec -- npm ci
mise run build:odin
mise exec -- npm run serve
```

Open `http://127.0.0.1:8080/player.html` and click **Start game**. Native:
`./build/odin-player/native/player.exe`.

For new Luau or Odin games, use [the SDK CLI](../sdk/README.md). For matching
native/browser examples in both languages:

```text
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

```text
npm run lint
npm run format:check
npm run test:odin
npm run test:sdk
npm run test:cartridge
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

## Formatting and linting

`mise run format` applies every formatter. `mise run format:check` checks without
writing. `mise run lint` runs all analyzers. Matching npm aliases remain available;
use `mise exec -- npm run <command>` without shell activation. Language-specific
npm commands include `format:odin`, `format:luau`, `lint:odin` and `lint:luau`.

| Language | Formatter | Analyzer |
| --- | --- | --- |
| JavaScript and HTML scripts | Prettier | ESLint |
| Odin | [odinfmt from OLS](https://github.com/DanielGavin/ols), `odinfmt.json` | Compiler `odin check -vet` |
| Luau | [StyLua](https://github.com/JohnnyMorganz/StyLua), `stylua.toml` | Official [luau-analyze](https://luau.org/getting-started/), `.luaurc` |

All repository Odin/Luau sources, examples, tests, templates and tracked generated
code are included. Downloaded dependencies, build outputs and editor SDK mirrors
are excluded. Odin packages are checked for their actual native or Wasm target;
native players also check the shared packages on Windows. Luau SDKs and typed
cartridges retain `--!strict`; the older demos use nonstrict inference. Enabled
Luau lint warnings fail the command through `lintErrors`, including in nonstrict
files. Formatter wrappers only invoke the community formatters and compare their
output; a bounded stable-layout check keeps generated files reproducible.

Configure editors to use the same `odinfmt.json` and `stylua.toml`. OLS supplies
Odin formatting; the StyLua extension supplies Luau formatting. `mise exec --
<editor>` gives an editor the pinned executables. No global PATH changes are
required.

The Luau SDK requires the new type solver for `read` table properties. Repository
lint and SDK checks explicitly select `--solver=new`. The checked-in VS Code
settings enable `luau-lsp.fflags.enableNewSolver`, select the standard Luau
platform, and disable automatic upstream flag synchronization and sourcemaps.
New Luau projects receive the same settings. Existing projects should use
`sdk/templates/luau-settings.json` as a reference when merging their own settings.
If the editor still reports `read keyword is illegal here`, run **Luau: Reload
Language Server** after the workspace settings load. Do not remove the `read`
annotations to silence these errors: they protect the SDK's immutable metadata.

Indentation uses spaces in every language. `.editorconfig` specifies four spaces
for Odin, Luau and C++, and two for JavaScript, HTML and configuration files.
Neither Odin nor Luau requires tabs; the optional Odin `-vet-tabs` rule is not
enabled. Formatter checks enforce the same space-based indentation.

## Task layout

`mise.toml` defines the project commands: `format`, `format:check`, `lint`,
`build:odin`, `build:rpg`, `build:racing`, `test`, and each `test:*` suite.
Dependency tasks are declared in `.mise/tasks/deps.toml`:

- `mise run deps:luau:configure` fetches/configures the executor's pinned sources.
- `mise run deps:luau` compiles the shared Wasm executor and depends on configure.

The dependency tasks declare source inputs and output files so mise can skip
unchanged builds. `mise run --force deps:luau` forces a rebuild. The SDK CLI calls
the same tasks rather than maintaining another dependency build cache. Asset
generators and packaging stay in JavaScript and invoke the pinned formatters
before writing generated sources. Rebuilding assets must leave format checks
passing. Project automation contains no shell scripts.

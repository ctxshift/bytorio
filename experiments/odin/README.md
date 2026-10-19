# Odin compiler and ABI probe

This is an isolated language-evaluation experiment. It leaves the Luau player and its native/browser builds unchanged. See [the evaluation](../../docs/odin-evaluation.md) for architectural conclusions and outstanding work.

`game.odin` exports scalar C-style procedures for initialization, input-driven movement, state inspection, and a bounds-check probe. It models the existing example's initial position, movement, action edge, and sound-event count. It does not draw a sprite, play audio, or reproduce the example's pointer input and visual bobbing.

`main_windows.odin` is a small native console driver, selected only for Windows. `verify.mjs` builds both variants, runs the Windows driver, and instantiates the identical freestanding Wasm binary in Node and a real browser through Playwright. It compares 120 updates and checks an intentional out-of-bounds trap. Native execution here means a separate Odin executable; the C++ player does not yet load Wasm guests.

## Reproduce on Windows

Prerequisites: Odin compiler, native linker prerequisites from the [Odin installation guide](https://odin-lang.org/docs/install/), Node.js, and this repository's pinned Playwright development dependency. The tested compiler is `dev-2026-10-nightly:84bc3fc` from [the dev-2026-10 release](https://github.com/odin-lang/Odin/releases/tag/dev-2026-10).

With `odin` on PATH, run from the repository root:

```powershell
npm ci
npx playwright install chromium
node experiments/odin/verify.mjs
```

An optional compiler path argument supports a local installation. The evaluation used:

```powershell
$env:PLAYER_BROWSER_CHANNEL = 'chrome'
node experiments/odin/verify.mjs .tools/odin/dist/odin.exe
```

That second command assumes the downloaded compiler has already been extracted to the stated local directory. It uses an installed Chrome instead of Playwright's Chromium. Compiler installation is not automated by this probe and does not change the accepted player's prerequisites.

Artifacts are written under ignored `build/odin/`, including `report.json`. The verifier records three sequential build wall times with `-o:minimal`; these are not cold-cache timings or an edit-to-first-frame benchmark. Each child process has a 30-second timeout. The probe requires Windows for its native executable; the generated Wasm itself was tested in Node and Chrome.

## Limits

This does not test allocator integration, heap caps, host offset validation, metering, worker recovery, C++ guest-engine embedding, source-level runtime diagnostics, actual graphics/audio, PNG packaging, or state-preserving reload. A decision to replace Luau requires those integration checks. Do not add this experiment to the production build or CI as a supported second game language without a separate decision.

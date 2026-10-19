# Fantasy console

A fantasy game console focused on small, mostly 2D games with occasional low-poly 3D, a fast development loop, and modern editors and AI tooling.

`free-machine` is a temporary repository codename. The product name is undecided; use neutral terminology in documentation, code comments, APIs, and identifiers so renaming does not become a project-wide migration.

The target language is **Odin for both games and the runtime**. The standalone native player has no webview; the browser player uses **WebAssembly**. Games compile into portable Wasm cartridge modules, with an experimental Luau executor available as well. The display supports **640×360** (default) and **320×180**, with runtime switching and crisp scaling. See [display modes](docs/display-modes.md) for the cartridge interface. Games should generally fit around **128 MB**, with a maximum around **512 MB**.

Distribution includes **self-contained PNG cartridges**: a viewable cartridge image carrying the complete game ROM. Native and browser players will load the original PNG file. The proposed encoding uses private PNG chunks; image resizing or re-encoding may discard the payload.

The **Odin reproduction is implemented**: a native Odin player and browser Odin/Wasm runtime load the identical game module with a movable sprite and sound. Use arrows/WASD to move and Space or click/tap for sound. The browser requires **Start game** to unlock audio. The earlier Luau/C++ slice remains available as a reference.

See [building and running Odin](docs/odin-development.md) for prerequisites, build commands, and verification. The SDK CLI, packed ROM/PNG loading, and larger graphics/audio features remain planned.

**The sprite RPG comparison is playable in both Luau and Odin.** Explore a village, accept a quest, fight a slime, and return a sunleaf. See [the RPG guide](docs/rpg-comparison.md) for builds, the comparison launcher, both game sources, and replay verification. Build both with `./tools/build-rpg.ps1`.

An [experimental Luau Wasm executor](experiments/luau-executor/README.md) runs both cartridges through the same Odin native/browser player. Its [updated benchmark results](experiments/luau-executor/BATCHED-RESULTS.md) compare batched drawing and compiled executor caching against the original rectangle path. Build with `npm run build:unified` and measure with `npm run bench:unified`.

- [Architecture](docs/architecture.md): accepted decisions, proposed machine profile, runtime boundaries, and open questions.
- [Implementation plan](docs/implementation-plan.md): milestones, acceptance criteria, and validation.
- [Odin development guide](docs/odin-development.md): build, run, controls, tests, and prototype limitations.
- [Reference development guide](docs/development.md): retained Luau/C++ build and checks.
- [DS versus 3DS target](docs/target-comparison.md): recommendation and supporting research.
- [Odin decision](docs/adr/0001-use-odin-for-games-and-runtime.md): Odin for games and runtime, with migration constraints.
- [Odin evaluation](docs/odin-evaluation.md): supporting research, an isolated compiler probe, and remaining integration risks.

The current recommendation is to retain the agreed 2D-first scope while leaving room for richer 3D later. A move to a 3DS-level fidelity target remains an open product decision.

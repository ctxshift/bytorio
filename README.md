# Fantasy console

A fantasy game console focused on small, mostly 2D games with occasional low-poly 3D, a fast development loop, and modern editors and AI tooling.

**[SDK 0.1.0](sdk/README.md)** provides typed Luau and Odin authoring APIs,
generated cartridge entry points, validated sprite/font assets, and a common
`new` / `check` / `build` / `run` / `watch` CLI. Start with
`npm run console -- new my-game`, then `npm run console -- run my-game --web`.
The [cartridge specification](docs/cartridge-spec.md) formalizes the implemented
2D preview profile; [API reference](sdk/api.md) and `npm run test:sdk` cover both SDKs.

`free-machine` is a temporary repository codename. The product name is undecided; use neutral terminology in documentation, code comments, APIs, and identifiers so renaming does not become a project-wide migration.

**Luau is the default cartridge language; Odin is also supported.** The runtime is Odin. The standalone native player has no webview; the browser player uses **WebAssembly**. Odin games compile into portable Wasm cartridge modules; Luau games run in the player-supplied Wasm executor. The display supports **640×360** (default) and **320×180**, with runtime switching and crisp scaling. See [display modes](docs/display-modes.md) for the cartridge interface. Games should generally fit around **128 MB**, with a maximum around **512 MB**; the implemented preview profile has smaller limits documented in the specification.

Distribution includes **self-contained PNG cartridges**: a viewable cartridge image carrying the complete game ROM. Native and browser players will load the original PNG file. The proposed encoding uses private PNG chunks; image resizing or re-encoding may discard the payload.

The **Odin reproduction is implemented**: a native Odin player and browser Odin/Wasm runtime load the identical game module with a movable sprite and sound. Use arrows/WASD to move and Space or click/tap for sound. The browser requires **Start game** to unlock audio. The earlier Luau/C++ slice remains available as a reference.

See [building and running Odin](docs/odin-development.md) for prerequisites, build commands, and verification. Packed ROM/PNG loading and larger graphics/audio features remain planned.

**The sprite RPG comparison is playable in both Luau and Odin.** Explore a village, accept a quest, fight a slime, and return a sunleaf. See [the RPG guide](docs/rpg-comparison.md) for builds, the comparison launcher, both game sources, and replay verification. Build both with `./tools/build-rpg.ps1`.

An [experimental Luau Wasm executor](experiments/luau-executor/README.md) runs both cartridges through the same Odin native/browser player. Its [RPG benchmark results](experiments/luau-executor/BATCHED-RESULTS.md) describe the earlier 384×216 prototype. The original RPG layout and historical comparison checks predate the two display modes.

**[Copper Circuit](docs/racing-demo.md) is the current racing comparison**, with independent Luau and Odin cartridges at 320×180, six rivals, boost, collisions and three-lap races. Build with `npm run build:racing`, verify with `npm run test:racing`, and measure with `npm run bench:racing`. See the [native/browser performance results](experiments/racing/RESULTS.md).

- [Architecture](docs/architecture.md): accepted decisions, proposed machine profile, runtime boundaries, and open questions.
- [Implementation plan](docs/implementation-plan.md): milestones, acceptance criteria, and validation.
- [Odin development guide](docs/odin-development.md): build, run, controls, tests, and prototype limitations.
- [Reference development guide](docs/development.md): retained Luau/C++ build and checks.
- [DS versus 3DS target](docs/target-comparison.md): recommendation and supporting research.
- [Odin decision](docs/adr/0001-use-odin-for-games-and-runtime.md): Odin for games and runtime, with migration constraints.
- [Odin evaluation](docs/odin-evaluation.md): supporting research, an isolated compiler probe, and remaining integration risks.

The current recommendation is to retain the agreed 2D-first scope while leaving room for richer 3D later. A move to a 3DS-level fidelity target remains an open product decision.

All project JavaScript uses ESLint and Prettier, including tooling, browser players,
examples, and benchmark scripts. After `npm ci`, run `npm run format` to apply the
shared formatting and `npm run lint:fix` for automatic lint fixes. Before committing,
run `npm run lint` and `npm run format:check`; CI enforces both. Generated builds,
downloaded tools, and dependencies are excluded. Project tools use Node.js and
PowerShell; no additional Python installation is required for project scripts.

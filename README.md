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

Distribution includes **self-contained PNG cartridges**: a viewable cartridge image carrying the complete game. Native and browser players load the original PNG file. The version-1 encoding uses a private PNG chunk; image resizing or re-encoding may discard the payload.

The native Odin player and browser Odin/Wasm runtime load the identical game module with a movable sprite and sound. Use arrows/WASD to move and Space or click/tap for sound. The browser requires **Start game** to unlock audio. Both cartridge languages use this player; C++ is limited to the Luau compiler/VM executor and development analyzer. The original C++ reference player has been removed.

See [building and running Odin](docs/odin-development.md) for prerequisites, build commands, and verification. **[PNG cartridges](docs/png-cartridges.md) are implemented** for both languages: `npm run console -- pack my-game`. Native and browser players load the same viewable PNG; the current 2D preview has a 2 MiB container limit. Larger ROMs and graphics/audio features remain planned.

**The sprite RPG comparison is playable in both Luau and Odin.** Explore a village, accept a quest, fight a slime, and return a sunleaf. See [the RPG guide](docs/rpg-comparison.md) for builds, the comparison launcher, both game sources, and replay verification. Build both with `mise run build:rpg`.

An [experimental Luau Wasm executor](experiments/luau-executor/README.md) runs both cartridges through the same Odin native/browser player. Its [RPG benchmark results](experiments/luau-executor/BATCHED-RESULTS.md) describe the earlier 384×216 prototype. The original RPG layout and historical comparison checks predate the two display modes.

**[Copper Circuit](docs/racing-demo.md) is the current racing comparison**, with independent Luau and Odin cartridges at 320×180, six rivals, boost, collisions and three-lap races. Build with `npm run build:racing`, verify with `npm run test:racing`, and measure with `npm run bench:racing`. See the [native/browser performance results](experiments/racing/RESULTS.md).

- [Architecture](docs/architecture.md): accepted decisions, proposed machine profile, runtime boundaries, and open questions.
- [Implementation plan](docs/implementation-plan.md): milestones, acceptance criteria, and validation.
- [Odin development guide](docs/odin-development.md): build, run, controls, tests, and prototype limitations.
- [Development guide](docs/development.md): current player, SDK, and Luau toolchain commands.
- [DS versus 3DS target](docs/target-comparison.md): recommendation and supporting research.
- [Odin decision](docs/adr/0001-use-odin-for-games-and-runtime.md): Odin for games and runtime, with migration constraints.
- [Odin evaluation](docs/odin-evaluation.md): supporting research, an isolated compiler probe, and remaining integration risks.

The current recommendation is to retain the agreed 2D-first scope while leaving room for richer 3D later. A move to a 3DS-level fidelity target remains an open product decision.

Run `mise install` and `mise exec -- npm ci` to prepare the pinned development tools.
`mise run format` formats JavaScript/HTML with Prettier, Odin with odinfmt, and Luau
with StyLua. `mise run lint` runs ESLint, `odin check -vet`, and `luau-analyze`.
CI enforces both lint and `mise run format:check`. Dependency build tasks live in
`.mise/tasks/`; project commands live in `mise.toml`. Project scripts use JavaScript.
See [development](docs/development.md) for setup, editor settings and task details.

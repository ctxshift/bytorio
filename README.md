# Fantasy console

A fantasy game console focused on small, mostly 2D games with occasional low-poly 3D, a fast development loop, and modern editors and AI tooling.

`free-machine` is a temporary repository codename. The product name is undecided; use neutral terminology in documentation, code comments, APIs, and identifiers so renaming does not become a project-wide migration.

The target language is **Odin for both games and the runtime**. The planned standalone native player has no webview; the browser player uses **WebAssembly**. Games are proposed to compile into portable Wasm cartridge modules. The agreed display is one **384 x 216** screen. Games should generally fit around **128 MB**, with a maximum around **512 MB**.

Distribution includes **self-contained PNG cartridges**: a viewable cartridge image carrying the complete game ROM. Native and browser players will load the original PNG file. The proposed encoding uses private PNG chunks; image resizing or re-encoding may discard the payload.

The existing executable slice is still the **Luau/C++ reference implementation**: native and browser players run the same example with a movable sprite and a sound. Use arrows/WASD to move and Space or click/tap for sound. The browser requires **Start game** to unlock audio. The Odin compiler probe passes, but the Odin player migration has not been implemented yet.

See [building and running](docs/development.md) for prerequisites, build commands, and verification. The SDK CLI, packed ROM/PNG loading, and larger graphics/audio features remain planned.

- [Architecture](docs/architecture.md): accepted decisions, proposed machine profile, runtime boundaries, and open questions.
- [Implementation plan](docs/implementation-plan.md): milestones, acceptance criteria, and validation.
- [Development guide](docs/development.md): build, run, controls, tests, and prototype limitations.
- [DS versus 3DS target](docs/target-comparison.md): recommendation and supporting research.
- [Odin decision](docs/adr/0001-use-odin-for-games-and-runtime.md): Odin for games and runtime, with migration constraints.
- [Odin evaluation](docs/odin-evaluation.md): supporting research, an isolated compiler probe, and remaining integration risks.

The current recommendation is to retain the agreed 2D-first scope while leaving room for richer 3D later. A move to a 3DS-level fidelity target remains an open product decision.

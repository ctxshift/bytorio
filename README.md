# Fantasy console

A fantasy game console focused on small, mostly 2D games with occasional low-poly 3D, a fast development loop, and modern editors and AI tooling.

`free-machine` is a temporary repository codename. The product name is undecided; use neutral terminology in documentation, code comments, APIs, and identifiers so renaming does not become a project-wide migration.

Games use **Luau**. A shared **C++** runtime runs as a standalone native application without a webview, and compiles to **WebAssembly** for browsers. The agreed display is one **384 x 216** screen. Games should generally fit around **128 MB**, with a maximum around **512 MB**.

Distribution includes **self-contained PNG cartridges**: a viewable cartridge image carrying the complete game ROM. Native and browser players will load the original PNG file. The proposed encoding uses private PNG chunks; image resizing or re-encoding may discard the payload.

The first executable slice is implemented: native and browser players run the same Luau example with a movable sprite and a sound. Use arrows/WASD to move and Space or click/tap for sound. The browser requires **Start game** to unlock audio.

See [building and running](docs/development.md) for prerequisites, build commands, and verification. The SDK CLI, packed ROM/PNG loading, and larger graphics/audio features remain planned.

- [Architecture](docs/architecture.md): accepted decisions, proposed machine profile, runtime boundaries, and open questions.
- [Implementation plan](docs/implementation-plan.md): milestones, acceptance criteria, and validation.
- [Development guide](docs/development.md): build, run, controls, tests, and prototype limitations.
- [DS versus 3DS target](docs/target-comparison.md): recommendation and supporting research.

The current recommendation is to retain the agreed 2D-first scope while leaving room for richer 3D later. A move to a 3DS-level fidelity target remains an open product decision.

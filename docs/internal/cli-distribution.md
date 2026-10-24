# Standalone CLI distribution plan

Status: implementation plan; no public installer or standalone release exists yet.
The [standalone CLI decision](../adr/0017-distribute-a-standalone-authoring-cli.md)
sets the user experience. This document describes the recommended implementation
and the checks needed before publishing installation instructions.

## Distribution shape

Use TypeScript and Bun for the authoring CLI, compiling a separate standalone
`byt` executable for each supported operating system and architecture. Users
install the executable without separately installing Bun, Node.js or mise.
The existing JavaScript CLI remains the source-checkout implementation until
the compiled replacement passes parity checks.

[Bun's executable support](https://bun.sh/docs/bundler/executables) covers
TypeScript/JavaScript, embedded files and explicitly included worker entry points.
That makes it a suitable packaging route, not proof that the current CLI can be
compiled unchanged. Preserve the CLI's timeout/isolation behavior when adapting
its worker-based cartridge checks. Keep repository build orchestration in mise;
this work does not require migrating every repository script to Bun.

Embed small, release-specific SDK schemas, templates and authoring files. Obtain
larger compiler and prebuilt player packages from a versioned release manifest.
Native executables and libraries must be installed into real cache directories
before execution or export; bundling the CLI does not eliminate those files.

## Project versions and dependency ownership

Recommend a project lockfile recording the exact SDK bundle, toolchain and
artifact checksums resolved for the project's declared SDK/profile. The lockfile
format and filename need definition during implementation. Do not silently
re-resolve an existing project against newer compiler releases.

Store dependency versions side by side in a user-level Bytorio cache. Projects
using the same version share downloads, while projects on different releases
retain compatible tools. Invoke cached tools by absolute resolved paths; do not
replace global Odin or Luau commands or depend on whichever version is on PATH.

| Component | Game-author distribution | Console-contributor setup today |
| --- | --- | --- |
| CLI JavaScript runtime | Included in the compiled Bun executable | Pinned Node.js |
| SDK interfaces, templates and schemas | Versioned SDK bundle | Source checkout |
| Luau analyzer | Verified prebuilt tool for Luau projects | Mise-managed analyzer |
| Luau executor/compiler bridge | Prebuilt compatible Wasm artifact | CMake/Emscripten build |
| Odin compiler | Pinned tool for Odin projects | Mise-managed compiler |
| Odin formatter used for generated source | Include a pinned formatter or remove this authoring dependency deliberately | OLS/odinfmt |
| Browser player, audio and decoder modules | Prebuilt release bundle | Odin/Emscripten builds |
| Native player and libraries | Prebuilt host-specific bundle with notices | Odin, linker, SDL and Wasmtime dependencies |
| CMake, Ninja, Emscripten, Python, native runtime linker tools | Not required merely to author a game | Required for relevant runtime source builds |

Check whether each target's Odin cartridge compiler needs additional linker
assets; package those with its toolchain instead of assuming the compiler alone
is sufficient. Luau-only authoring must not install Odin merely to rebuild a player.

Mise should install and pin the `byt` release, not independently choose Odin and
Luau versions for that project. Optional generated mise configuration can select
`byt`; the project lockfile remains the authority for its SDK toolchain.
The [mise GitHub backend](https://mise.jdx.dev/dev-tools/backends/github.html)
can install release assets. Publish the exact installation command only after
the release repository, asset names and supported platforms are established.

## Downloads, updates and recovery

- Release metadata identifies platform, version, download size, checksums and
  required licenses. Verify against trusted release metadata before extraction.
- Show required downloads before fetching them. Install into a staging directory
  and publish a complete cache entry only after verification; interrupted
  downloads must not replace a working toolchain.
- Reuse verified cache entries and support offline builds once the required
  bundles are installed. Missing offline dependencies should name what is needed.
- Make toolchain updates explicit. Updating the CLI must not silently migrate
  game sources, profiles, lockfiles or existing project dependencies.
- Provide diagnostics for selected tools, cache locations and missing components.
  Command names for diagnostics, updates and cache cleanup are not implemented yet.
- Keep the game project and cached toolchains after CLI uninstall unless the user
  explicitly requests their removal. Preserve attribution in exported players.

## Work required in the current implementation

1. Separate the authoring library from checkout paths in `tools/sdk/project.mjs`.
   It currently reads SDK files relative to the repository and invokes
   `build:odin` and `deps:luau` during game checks.
2. Replace authoring-time runtime builds with a release-bundle resolver. Keep the
   source-build provider available for console contributors.
3. Introduce typed CLI interfaces, the toolchain manifest/lockfile and cache
   management. Preserve existing manifest and cartridge compatibility.
4. Embed assets and the smoke-check worker explicitly. Replace assumptions about
   `import.meta.url`, executable paths and loose worker files where necessary.
5. Build and test the standalone Windows x64 release first. Add other OS/CPU
   targets only after their full authoring and export paths pass qualification.
6. Add installer/download instructions and optional mise integration. Do not
   publish an npm-install command for the current private repository package.

## Release acceptance

On a clean machine without Node, Bun, mise or a console checkout, create, check,
run and pack both Luau and Odin starter games. Verify imported models, embedded
templates, worker failure recovery, native/browser exports and license contents.
Test project paths with spaces, concurrent dependency requests, interrupted and
corrupt downloads, unsupported platforms, offline reuse and two projects pinned
to different toolchains. Compile each target separately and test it on that target;
cross-compilation alone does not establish platform support.

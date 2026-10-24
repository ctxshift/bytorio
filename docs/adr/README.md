# Architectural decisions

These records explain the architectural choices that shape Bytorio and why they
were made. Each record owns one concern; exact interfaces, limits and supported
targets belong in the linked area documentation. An accepted architectural
direction does not promote an experimental capability profile to stable.

## Runtime and execution

- [0001: Odin for the shared runtime](0001-use-odin-for-games-and-runtime.md)
- [0002: Luau and Odin for cartridge authoring](0002-support-luau-and-odin-cartridges.md)
- [0003: WebAssembly execution boundary](0003-execute-cartridges-through-a-wasm-boundary.md)
- [0004: Standalone native player](0004-provide-a-standalone-native-player.md)
- [0006: Explicit portable profiles](0006-negotiate-explicit-portable-profiles.md)
- [0010: Browser Worker isolation](0010-isolate-browser-game-execution-in-a-worker.md)

## Cartridge data and resources

- [0005: Complete PNG cartridges](0005-distribute-complete-games-as-png-cartridges.md)
- [0007: Immutable content outside guest memory](0007-separate-cartridge-content-from-guest-memory.md)
- [0008: Transactional typed resources](0008-publish-resource-changes-transactionally.md)
- [0015: Opaque save snapshots](0015-persist-opaque-save-snapshots.md)
- [0016: Explicit stable save identity](0016-declare-stable-save-identity.md)
- [0017: Standalone authoring CLI](0017-distribute-a-standalone-authoring-cli.md)

## Timing, audio and graphics

- [0009: Simulation independent of rendering](0009-separate-simulation-from-render-cadence.md)
- [0011: Audio production separate from device delivery](0011-separate-audio-production-from-device-delivery.md)
- [0012: Shared libvorbisfile decoder](0012-use-libvorbisfile-on-both-hosts.md)
- [0013: Optional GPU rendering](0013-keep-gpu-rendering-optional.md)
- [0014: Development-time model import](0014-import-model-formats-during-development.md)

See the [architecture overview](../architecture.md) for how these choices fit
together, and the [development guide](../development.md) for working on the code.

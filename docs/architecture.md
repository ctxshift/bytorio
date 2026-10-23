# Bytorio architecture

Bytorio is a software game console for making and sharing small games, with a
2D focus and experimental 3D capabilities. It is an independent machine, not an
emulator for another console's hardware or game binaries.

The [architectural decision records](adr/README.md) explain the choices and their
trade-offs. This page maps the system; the linked specifications define exact
interfaces, limits and supported behavior.

## Runtime and game languages

The [shared runtime is Odin](adr/0001-use-odin-for-games-and-runtime.md).
[Cartridge authors can use Luau or Odin](adr/0002-support-luau-and-odin-cartridges.md),
with Luau as the default for new projects. These are separate choices: using
Odin to implement the console does not remove Luau from game development.

```text
Odin game source -> game WebAssembly module
Luau game source -> player-supplied Luau WebAssembly executor
                              |
                   validated guest interface
                              |
          shared Odin timing, resources, graphics and audio
                      /                         \
       native platform adapters       browser platform adapters
```

The [WebAssembly boundary](adr/0003-execute-cartridges-through-a-wasm-boundary.md)
separates game memory from host storage and exposes only console services.
The [native player is standalone](adr/0004-provide-a-standalone-native-player.md);
its users need neither a webview nor the development toolchain.
The browser runs game execution in a
[Worker with bounded messages and watchdog recovery](adr/0010-isolate-browser-game-execution-in-a-worker.md).
Neither host grants cartridges arbitrary filesystem or network access.

See the [legacy ABI specification](cartridge-spec.md),
[current profile contracts](resource-profile.md) and
[machine-readable SDK contract](../sdk/contract.json) for guest exports and
validation. The [development guide](development.md) covers host dependencies,
pinned tools and build commands.

## Compatibility and ownership

[Explicit capability profiles](adr/0006-negotiate-explicit-portable-profiles.md)
define portable requirements independently of hardware speed. Players validate a
cartridge's requirements before initialization. Experimental profiles remain
opt-ins; an implemented preview is not automatically part of the stable console.
See [profile negotiation](resource-profile.md) for compatibility rules.

The runtime owns graphics and audio resources, accessed by typed generation
handles. [Transactional resource submission](adr/0008-publish-resource-changes-transactionally.md)
keeps rejected packets from publishing partial changes. The
[resource specification](resource-av-spec.md) defines lifetimes, budgets and
commit behavior; the [SDK resource guide](../sdk/resources.md) explains usage.

## Cartridge data and saves

A [PNG cartridge](adr/0005-distribute-complete-games-as-png-cartridges.md) contains
cover art and the complete game payload. The reusable player and its dependencies
are separate from the cartridge. The [PNG specification](png-cartridges.md)
defines the envelope and parser rules.

[Immutable indexed content](adr/0007-separate-cartridge-content-from-guest-memory.md)
lets games read bounded byte ranges without expanding guest memory to fit the
whole cartridge. The host retains backing bytes until unload; decoded resources
have their own ownership and accounting. See [indexed content](indexed-content.md)
for its interface and limits.

Saves are [opaque committed snapshots](adr/0015-persist-opaque-save-snapshots.md).
An [explicit stable save identity](adr/0016-declare-stable-save-identity.md) lets
compatible builds retain progress independently of code or cover changes. Games
own save-format compatibility; hosts own persistence and report failures.
The [save reference](../sdk/save.md) defines identity, migration and completion.

## Timing, rendering and audio

[Simulation is independent of render cadence](adr/0009-separate-simulation-from-render-cadence.md).
The [frame-pacing guide](frame-pacing.md) defines fixed updates, host rendering
preferences, catch-up and pause behavior. The [display guide](display-modes.md)
defines the logical screen modes and presentation scaling.

[CPU rendering is the default, with optional GPU execution](adr/0013-keep-gpu-rendering-optional.md).
See [2D graphics](../sdk/graphics.md), [compact 3D](compact-3d.md),
[textured 3D](textured-3d.md), [billboards](billboards.md) and
[scene effects](3d-effects.md) for their contracts and preview scope.
[Model import happens during development](adr/0014-import-model-formats-during-development.md),
with the supported artist-format subset defined in [model importing](model-import.md).

[Audio production is separate from device delivery](adr/0011-separate-audio-production-from-device-delivery.md).
The shared runtime owns stream timing and mixing; host adapters deliver audio.
[Libvorbisfile is the chosen Ogg decoder on both hosts](adr/0012-use-libvorbisfile-on-both-hosts.md).
See [audio](../sdk/audio.md), [synthesis](../sdk/synthesis.md) and
[Ogg integration](ogg-streaming-integration.md) for APIs, scheduling and limits.

## Boundaries and open work

Protocol limits are not performance promises. Cartridge storage, guest memory,
decoded resources, GPU allocations and process overhead are distinct quantities;
a logical resource quota is not a cap on total browser or native process memory.
Current supported targets and qualification limits are recorded in
[profile conformance](resource-profile.md#verification-and-supported-targets).

Minimum-device qualification, additional native platforms and enforcement of the
native Vorbis allocator cap remain separate work. A blocked game Worker or native
host loop can still starve audio production. Fixed simulation ticks do not by
themselves establish cross-platform deterministic replay or rollback networking.

The [implementation plan](implementation-plan.md) contains milestone planning and
completion evidence, rather than compatibility guarantees. Research such as
[DS versus 3DS targets](target-comparison.md) and
[pixel-stability experiments](../experiments/voxel-resolution/docs/pixel-stability-research.md) explores possibilities;
it does not change accepted architecture or a published profile.

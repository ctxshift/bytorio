# Sprite RPG language comparison

**Mossglen: The Sunleaf** is a small quest implemented in Luau and Odin using
SDK 0.1.0. Both cartridges run through the same Odin player on native and browser
hosts, at 640×360. The original 384×216 art layout is preserved inside that
framebuffer, with its historical replay goldens retained for regression checks.

Walk to the healer beside the red house, accept the quest, cross the eastern
bridge, defeat the moss slime, collect the sunleaf, and return it. Battles offer
Attack, Guard, and one healing potion. Defeat restores the player in the village.

## Build and play

Install the [development prerequisites](development.md), then from the repository root:

```text
npm ci
npm run build:rpg
npm run serve:rpg
```

Open `http://127.0.0.1:8080/comparison.html` and choose a language. Click
**Start game** for audio. Arrows/WASD move; Space talks and confirms. In battle,
arrows select an action and Space takes a turn. On-screen controls use the same
input path. Physical touch hardware remains unverified.

Both standalone choices use the same executable:

```text
# Odin
./build/unified-player/native/player.exe --game build/unified-player/native/rpg-odin.png
# Luau
./build/unified-player/native/player.exe --game build/unified-player/native/rpg-luau.png
```

`build:unified` remains an alias for `build:rpg`. The earlier C++ player,
rectangle-expansion helper, separate RPG staging path, and CTest suite have been
removed. C++ remains in the Luau executor and development analyzer only.

## Compare the code

| Concern | Luau | Odin |
| --- | --- | --- |
| Gameplay and presentation | [main.luau](../examples/rpg-luau/main.luau) | [main.odin](../examples/rpg-odin/main.odin) |
| Bytorio API | [Luau SDK](../sdk/luau/bytorio.luau) | [Odin SDK](../sdk/odin/bytorio/bytorio.odin) |
| Lifecycle | SDK game callbacks | SDK-generated [entry point](../examples/rpg-odin/cartridge.odin) |
| Assets | Bundled graphics packet | Compiled graphics packet |

[Shared assets](../examples/rpg-shared/assets.json) define the palette, sprites,
map, and bitmap font. `tools/build-rpg-assets.mjs` generates checked-in asset
modules and `build/rpg/batched.luau`. Gameplay implementations are handwritten;
asset generation does not translate rules between languages.

Both use explicit state machines, tile collision, input edges, eight-tick held
movement, and matching turn resolution. Sprites and text use bounded commands
expanded by the shared Odin renderer. The [cartridge specification](cartridge-spec.md)
and [SDK API](../sdk/api.md) define the current contract. The
[executor guide](../experiments/luau-executor/README.md) documents integration and
historical performance measurements.

## Verification

```text
npm run test:rpg
npm run test:display
```

The shared-player harness checks the 134-tick quest and 76-tick defeat/recovery
routes against historical art-region goldens, then compares full-frame output
and cumulative sound events across Node, native, and browser execution in both
languages. It also checks native SDL audio, browser audio, diagnostics, reload,
and compiled-executor cache reuse/invalidation. Reports and screenshots go in
`build/unified-player/benchmark-batched/`. The test uses one sample per variant;
use `npm run bench:unified` for repeated performance measurements.

The demo has no saves, music, custom sound samples, or full 3D pipeline. Both
languages currently trigger the same built-in sound cue. Automated audio checks
verify the output path; physical speaker and controller behavior require live testing.

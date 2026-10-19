# Sprite RPG language comparison

**Mossglen: The Sunleaf** is a small complete quest implemented separately in Luau and Odin. Both versions use the same 384 × 216 display, 32 × 20 tile world, palette, sprite art, bitmap font, game rules, and input sequence. This is a playable language comparison, not a finished SDK or commercial RPG.

Walk to the healer beside the red house, accept the quest, cross the eastern bridge, defeat the moss slime, collect the golden sunleaf, and return it. Battles offer Attack, Guard, and one healing potion. Defeat returns the player to the village with restored health and supplies. The quest can also be accepted after defeating the slime.

## Build and play

From the repository root, with the [Odin prerequisites](odin-development.md) and [C++/Emscripten prerequisites](development.md) installed:

```powershell
./tools/build-rpg.ps1
$env:PORT = '8081'
npm run serve:rpg
```

Open `http://127.0.0.1:8081/player.html` and choose a language. Click **Start game** to enable sound. Arrows/WASD move; Space talks and confirms. In battle, arrows change the selection and Space takes a turn. The staged site also provides pointer-operated direction and action buttons. Their event path is tested in desktop Chrome; physical touch hardware remains unverified.

Standalone Windows players:

```powershell
./build/rpg-luau/native/Release/player.exe
./build/rpg-odin/native/player.exe
```

Individual builds can use `./tools/build.ps1 native -Game rpg`, `./tools/build.ps1 web -Game rpg`, or `./tools/build-odin.ps1 all -Game rpg -Fixtures`. The original hello examples remain the default when `-Game` is omitted. Run `node tools/stage-rpg.mjs` after rebuilding to refresh the comparison site.

## Where to compare the code

| Concern | Luau | Odin |
| --- | --- | --- |
| Gameplay and presentation | [main.luau](../examples/rpg-luau/main.luau) | [main.odin](../examples/rpg-odin/main.odin) |
| Guest drawing helpers | [graphics.luau](../examples/rpg-luau/graphics.luau) | [graphics SDK](../runtime/odin/graphics/graphics.odin), [text helpers](../examples/rpg-odin/drawing.odin) |
| Player integration | Existing Luau module callbacks | [cartridge.odin](../examples/rpg-odin/cartridge.odin) |
| Cartridge assets | Bundled before the game source | Compiled into guest memory |

[Shared assets](../examples/rpg-shared/assets.json) are the source of truth for the palette, sprites, map, and font. `tools/build-rpg-assets.mjs` generates the checked-in Odin asset module and bundles the Luau source under `build/rpg/main.luau`. Each game carries its own assets; neither RPG uses the player's original built-in demo sprite.

The two gameplay implementations are handwritten. Asset generation does not translate gameplay between languages. Both use the same explicit state machine, tile collision rules, input edges, eight-tick held movement cadence, and turn resolution. Presentation and rules intentionally remain easy to read together in this small example. No ECS, general quest framework, or other game engine is required.

The console interface now supports opaque, clipped RGBA rectangles. Guest helpers build sprites and text from those primitives. Odin exposes an optional bounded display list: `game_commands()` returns its guest-memory offset and `game_command_count()` its length. Each command contains five little-endian 32-bit fields: signed x/y/width/height and an unsigned RGBA color. The player allows at most 16,384 commands, validates guest-memory bounds and coordinates, and copies the commands before rendering. The original 40-byte frame contract remains supported. Coordinates range from -4096 to 4096; width and height range from 0 to 4096. Sprites use horizontal runs of palette pixels, rather than one command per pixel. This simple software path is sufficient for the experiment; it is not the final graphics architecture.

## Verification

```powershell
# Use PLAYER_BROWSER_CHANNEL=chrome if testing an installed Chrome instead of Playwright Chromium.
npm run test:rpg
ctest --test-dir build/rpg-luau/native -C Release --output-on-failure
```

The verifier checks a 134-tick quest route and a 76-tick defeat/recovery route, asserting collision, held-action behavior, quest flags, health, damage, guard, potion exhaustion, victory, collection, completion, and repeat dialogue. It compares framebuffer hashes and cumulative sound requests after **every tick** across Luau native, Odin native, Luau browser, Odin browser, and a Node Wasm reference. The native and browser Odin players use identical cartridge bytes. It also checks live keyboard input and non-silent browser audio, and rejects oversized display lists, invalid guest offsets, and invalid rectangle dimensions on native and browser hosts. Reports and screenshots are written to `build/rpg/verification/`.

The Luau browser's `?replay` mode enables manual ticks through `Module._player_step(buttonMask)`. The Odin native player's `--replay file` accepts one decimal button mask per line; the Luau native `rpg_replay` utility accepts a source bundle and the same file. This tooling makes differences reproducible without depending on wall-clock keyboard timing.

## Limits and interpretation

Progress is session-only and resets on reload. Persistent saves, PNG cartridge loading, music, distinct sound effects, sprite sorting/clipping features, and polished animation remain future work. This experiment uses the original shared sound cue for event feedback. Browser input buttons are supplied by the launcher, outside the cartridge; native players support keyboard and the existing controller input.

Parity proves that both languages can express this RPG and run consistently through our two players. It does **not** measure human authoring speed, AI success rate, or a DS-scale game's performance. The tiny state model fits fixed storage, so this comparison does not exercise Odin allocator/lifetime management or Luau collection-heavy gameplay. Odin's ABI glue is kept separate from gameplay so it does not dominate the authoring comparison. The accepted Odin architecture remains in place while the alternate Luau game supplies evidence for the language decision.

# Batched sprite and text commands

Both RPG guests now upload a cartridge-owned atlas/font packet once and submit high-level sprite and text operations. The shared Odin renderer expands these operations. The original 20-byte rectangle command ABI remains supported.

Guests advertising `game_command_stride() == 32` use this little-endian record:

| Offset | Field | Meaning |
| --- | --- | --- |
| 0 | u32 kind | 0 rectangle, 1 sprite, 2 text |
| 4, 8 | i32 x, y | Screen position |
| 12, 16 | i32 w, h | Rectangle dimensions; sprite handle and scale for sprites |
| 20 | u32 color | Opaque RGBA for rectangles/text |
| 24, 28 | u32 offset, length | Slice of the frame's text buffer |

`game_text()` and `game_text_size()` expose the frame's text bytes. Limits are 16,384 commands, 16 KiB total text, 1,024 bytes per text operation, sprite scales 1–8, and coordinates -4096 through 4096. Text supports ASCII and newline. Buffers are range-checked and copied into host-owned storage before rendering.

`game_assets()` and `game_assets_size()` expose an immutable atlas/font packet, loaded after game initialization. Its 16-byte header contains four u32 values: magic `0x31584647` (`GFX1`), sprite count (1–256), palette count (16), and glyph count (128). It is followed by 16 opaque RGBA colors, 256 palette-index bytes per 16×16 sprite (255 means transparent), then seven five-bit rows per ASCII glyph. Length, palette indices, and font rows are validated before the atlas becomes usable.

The asset generator creates the packet from the existing shared art. Odin embeds the packet. Luau embeds a base64 representation decoded once by its executor. The unified player uses `build/rpg/batched.luau`, which avoids bundling a second copy of the art as string rows. The legacy C++ player and its full-source rectangle fallback have been removed.

The initial RPG frame now contains **255 commands**, down from **8,582**. The saved pre-optimization hashes in `tests/rpg/parity.json` cover the quest and defeat routes, so both guests must preserve the original pixels and sound requests.

Run `node experiments/luau-executor/verify-drawing.mjs` after `npm run build:unified` to check atlas validation, invalid operations, handles, dimensions, text slices, clipping, and command count. The benchmark harness also checks every frame against the original hashes.

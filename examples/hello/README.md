# Sprite and sound

Run `mise run build`, then `mise run serve` here. Open
`http://127.0.0.1:8087/`. The standalone player is `build/native/player.exe`.

`odin/` owns the minimal ABI 1 cartridge used to exercise the shared player's
boot path. `tools/build.mjs` exports that verified player and cartridge into
this project's `build/` directory. See the
[native/browser guide](../../docs/odin-development.md).

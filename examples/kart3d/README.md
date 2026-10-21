# Sunline Sprint

Run `mise run build`, then `mise run serve` from this directory. Open
`http://127.0.0.1:8082/`. Choose Odin or Luau and start the game.
CPU is the default; the launcher provides separate opt-in GPU links.

`odin/` and `luau/` contain the games, `shared/` contains the launcher, `tools/`
contains the course generator, builder, replay checks and benchmark, and `tests/`
contains independent simulation expectations. Exports and reports go in `build/`.

Use `mise run test`, `mise run test:gpu`, `mise run generate` or
`mise run benchmark` for the corresponding project tasks. See the
[game guide](../../docs/kart-racing.md) for controls, measurements and limits.

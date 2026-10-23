# Mossglen RPG

Run `mise run build`, then `mise run serve` here. Open
`http://127.0.0.1:8083/comparison.html`.

The language variants live in `odin/` and `luau/`; `shared/` owns their artwork,
controls and launcher. `tools/` owns asset generation and replay measurements.
Use `mise run generate`, `mise run test` or `mise run benchmark` as needed.
Exports live in `build/player/{native,web}`. See the
[RPG guide](docs/rpg-comparison.md).

# Copper Circuit

Run `mise run build`, then `mise run serve` here. Open
`http://127.0.0.1:8084/comparison.html`.

`odin/`, `luau/` and `shared/` contain the two games and their common controls
and launcher. `tools/` owns asset generation, replay verification and benchmarks.
Use `mise run generate`, `mise run test` or `mise run benchmark` as needed.
The benchmark runs its replay check first to produce the required input trace.
Exports live in `build/player/{native,web}`. See the
[racing guide](docs/racing-demo.md).

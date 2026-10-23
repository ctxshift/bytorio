# Sunline Sprint

Run `mise run build`, then `mise run serve` from this directory. Open
`http://127.0.0.1:8082/`. Choose Odin or Luau and start the game.
CPU is the default; the launcher provides separate opt-in GPU links.

`odin/` and `luau/` contain the games, `shared/` contains the launcher, `tools/`
contains the course generator, builder, replay checks and benchmark, and `tests/`
contains independent simulation expectations. Exports and reports go in `build/`.

`assets/` contains original glTF inputs and their shared atlas. Checked imported
modules support matching low/high karts and runtime LOD. Hold Space and press Q
to cycle automatic, low and high detail; plain Q changes resolution. Detail is
independent of CPU/GPU selection. See [asset authoring](assets/README.md).

Use `mise run test`, `mise run test:gpu`, `mise run generate` or
`mise run benchmark` for the corresponding project tasks. See the
[game guide](docs/kart-racing.md) for controls, measurements and limits.

`mise run benchmark:quality` measures moving karts through both SDKs and hosts,
at both display sizes with SSAA off, 2× and up to 1080p. CPU and explicitly
enabled resident GPU cases run serially. Raw phase timings, memory and attachment
traffic remain in `build/benchmarks/`. Work throughput excludes main-thread
delivery and display scanout; it is not a delivered-FPS measurement.

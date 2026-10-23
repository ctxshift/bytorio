# Imported rigid model

Run `mise run build`, then `mise run serve` here. Open
`http://127.0.0.1:8085/`.

`assets/` contains the original glTF input. `odin/` and `luau/` contain matching
SDK examples and checked generated model modules. `tools/` owns importing,
building and measurement. Use `mise run generate` after editing the model and
`mise run benchmark` to measure the attachment workload. Exports live in `build/`.
The SDK's model-import conformance remains in `mise run //:test:models`.
See the [model authoring guide](../../docs/model-import.md) and the
[attachment measurement report](docs/gpu-attachment-measurements.md).

# Typed resource examples

Run `mise run build`, then `mise run serve` here. Open
`http://127.0.0.1:8088/` to select graphics or synthesis in either SDK.

`graphics/` and `synthesis/` own the playable sources. `lifecycle/` contains
small resource ownership examples. `tools/` builds their exports in `build/`.
The root SDK graphics, synthesis and profile conformance suites also exercise
these sources against independent expected results.
See the [resource profile](../../docs/resource-profile.md).

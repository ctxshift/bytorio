# Use Odin for games and the runtime

Accepted 2026-10-19: use Odin for both game development and the console runtime, replacing the initial Luau/C++ direction. This gives the project one primary language with explicit data layout and allocation control; the working Luau/C++ slice remains a behavioral reference until an Odin implementation matches its native/browser functionality and failure handling.

The proposed execution model is Odin games compiled to portable Wasm cartridges, loaded by an Odin native player through an embedded Wasm engine and by the browser's Wasm engine on web. The guest ABI, native engine, browser worker bridge, and development reload workflow still require implementation and measurement. Third-party libraries may use other languages and expose C interfaces; this decision does not require rewriting SDL or a Wasm engine in Odin.

The standalone native requirement, 384 x 216 display, 2D-first scope, approximate 128/512 MB package goals, and full self-contained PNG cartridges remain unchanged. See the [architecture](../architecture.md), [migration plan](../implementation-plan.md), and [evaluation evidence](../odin-evaluation.md).

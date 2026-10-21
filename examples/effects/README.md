# Effects garden

Run `mise run build` and `mise run serve` here, then open
`http://127.0.0.1:8089/`. Both SDKs demonstrate cutout artwork, depth-tested
premultiplied smoke and additive particles. Left/right orbits; Action selects
640×360. CPU is the default, with optional GPU controls in each player.

`mise run test` checks native/browser CPU and `mise run test:gpu` checks the
optional hardware matrix. See [the contract](../../docs/3d-effects.md) for
blending, ordering, ownership and conformance details.

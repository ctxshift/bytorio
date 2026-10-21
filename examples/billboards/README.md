# Billboard garden

Run `mise run build`, then `mise run serve` here. Open
`http://127.0.0.1:8086/`.

`odin/` and `luau/` implement the same garden. The launcher and builder belong
to this project; exports live in `build/`. SDK billboard conformance remains in
`mise run //:test:billboards`, with the optional GPU gate at
`mise run //:test:billboards:gpu`. See the
[billboard guide](../../docs/billboards.md).

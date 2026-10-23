# Execute cartridges through a WebAssembly boundary

Run Odin cartridges as freestanding core WebAssembly and Luau cartridges through
a player-supplied WebAssembly executor, so the same cartridge works on native and
browser hosts without loading a native game library into the player.
Give each session isolated guest memory and a versioned scalar-and-buffer
interface with explicitly allowed imports, validating offsets, lengths and
requirements before accessing host data.
This preserves portability and limits game access to console services, at the
cost of an embedded native engine and bounded data transfers across the boundary.

Interface details: [legacy ABI](../cartridge-spec.md) and
[current profile contracts](../resource-profile.md).

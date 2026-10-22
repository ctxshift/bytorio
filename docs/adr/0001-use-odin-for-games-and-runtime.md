# Use Odin for the runtime; Odin or Luau for games

Accepted 2026-10-19; clarified 2026-10-21: implement the console runtime in Odin. Cartridge (game) authors may use either Odin or Luau. Luau remains a supported development language, not a temporary reference or a language scheduled for removal. Luau is the default for new projects; choosing Odin provides explicit data layout and allocation control.

Both cartridge languages use the same Odin runtime on native and browser hosts. Odin game code compiles to a portable Wasm module. Luau game code runs through the player-supplied Luau Wasm executor. Both SDKs expose the console's shared services and support portable PNG cartridges. See the [SDK guide](../../sdk/README.md) and [cartridge specification](../cartridge-spec.md) for their contracts.

The runtime language decision replaces the original C++ player, not Luau cartridge development. C++ remains in the Luau compiler/VM executor and development analyzer. Third-party libraries may use other languages and expose C interfaces; this decision does not require rewriting SDL or a Wasm engine in Odin.

The standalone native player, browser player, and portable PNG cartridge requirements apply to both game languages. Display modes, resource limits, and supported profiles are defined separately from the language choice. See the [architecture](../architecture.md), [implementation plan](../implementation-plan.md), and [evaluation evidence](../odin-evaluation.md).

# Use Odin for the shared console runtime

Implement the console runtime in Odin, sharing console behavior between native
and browser hosts to avoid maintaining two implementations of the same machine.
Odin provides explicit data layout and allocation control while allowing platform
services and third-party libraries through foreign interfaces.
The runtime language does not constrain [cartridge authoring languages](0002-support-luau-and-odin-cartridges.md)
or require dependencies to be rewritten in Odin.

# Readable language examples

The canonical resource lifecycle examples are
[Luau](../examples/resources/lifecycle/luau/main.luau) and
[Odin](../examples/resources/lifecycle/odin/main.odin). They were promoted from the
resource conformance fixtures; the verifier consumes these exact files, rather
than maintaining separate copies. They illustrate code structure and resource
ownership, not a playable graphics or audio demo: drawing only clears the screen.

Run `mise run validate test:resources` from the repository root. The existing
suite builds both examples, exercises native and browser hosts, checks packet
layouts and independent expected resource data, and preserves malformed-packet,
rollback, handle, reload and accounting checks. Run `mise run lint` for language
checks; both examples are included in normal formatting and analyzer discovery.

## Structure and ownership

Keep imports, semantic constants, persistent state, helpers and lifecycle
functions visually separate. Each function has a single clear job. The examples
use named dimensions and sample parameters, while literal colors and fixed replay
ticks remain local data. Packet layout values belong to the shared schema, not
new constants in each language.

| Phase | Behavior |
| --- | --- |
| Init | Create/upload a 2×2 texture and four-frame stereo PCM sample |
| After upload | Zero staging buffers to prove uploads own snapshots |
| Tick 2 | Replace texture contents, then reuse staging memory |
| Tick 3 | Replace PCM contents |
| Tick 4 | Destroy both host resources |
| Tick 5 | Create a differently shaped texture to exercise slot reuse |
| Up input | Intentionally upload through a destroyed handle; expect rejection |

The deliberately invalid Up path is isolated and named as a negative test; do not
copy it into normal game logic. The SDK/host reports the rejected transaction.
Cartridge callbacks run inside the SDK's lifecycle wrapper, so they do not call
transport `configure`, `begin`, `end` or `ack` themselves.

Luau staging buffers are managed values. Odin staging buffers use the cartridge
allocator; this short fixture retains them for the guest instance lifetime.
For short-lived Odin buffers, pair `data.pixels` with `defer data.free_pixels`,
and `data.pcm` with `defer data.free_pcm` after their last use. Destroying a host
texture/sample does not free a guest staging buffer. See the native
[registry test](../tests/resources/registry_test.odin) for that allocation pattern
and explicit transport setup outside a cartridge callback.

## Host-side tests and tooling

In an Odin host test, reset the registry and configure transport with the same
session, begin the callback, enqueue operations, end it, submit the packet, check
acceptance or rollback, and acknowledge the sequence. Copy the real helper
signature from existing tests. `testing.expect` accepts a message;
`testing.expect_value`'s fourth argument is a source location, not a message.
Keep one expected invariant per assertion, including independent expected bytes
or pixels when testing a shared implementation.

For JavaScript process orchestration, use the
[validation runner](../tools/validation-runner.mjs) as the executable reference:
pass argument arrays, retain command output, preserve exit status, and test
failure behavior. C++ remains limited to the Luau bridge; follow its existing
translation units and compilation database, with `mise run format:cpp` and
`mise run lint:cpp`. Do not add a second C++ runtime example.

Formatter output is a mechanical check, not a readability review. Preserve clear
grouping when editing and inspect the resulting diff before broader validation.

# Experimental typed resources: milestone 4a

The current native player and browser Worker support an **internal development
transport**, version 1, for texture and PCM resource ownership. This is the first
implemented slice of [the resource proposal](../docs/resource-av-spec.md).
It does not advertise SDK 0.2.0, ABI 2, or `resource-av-1`; the existing SDK 0.1.0 /
ABI 1 cartridge contract and PNG readers are unchanged. These experimental calls
require matching players from this checkout. They are not portable to older
players merely because the cartridge still uses the existing container profile.

Resources can be created, uploaded, edited and destroyed. They cannot yet be
drawn or played: explicit passes arrive in 4b and the mixer in 4c. Existing sprite,
text and sound-cue calls continue to work.

## SDK operations

Luau uses `console.data`, `console.gfx`, and `console.audio`. Odin imports
`data "sdk:data"`, `gfx "sdk:gfx"`, and `audio "sdk:audio"`.

| Operation | Luau | Odin |
| --- | --- | --- |
| Pixel buffer | `data.pixels("rgba8",w,h)` or `"index8"` | `data.pixels(.RGBA8,w,h)` or `.Index8` |
| PCM buffer | `data.pcm(frames,channels)` | `data.pcm(frames,channels)` |
| Texture | `gfx.texture({format="rgba8",width=w,height=h})` | `gfx.texture({.RGBA8,w,h})` |
| Upload | `gfx.upload(texture,{x=0,y=0,width=w,height=h},pixels,opts)` | `gfx.upload(texture,{0,0,w,h},pixels,opts)` |
| Sample | `audio.sample({frames=n,channels=2,rate=48000},pcm)` | `audio.sample({n,2,48000},pcm)` |
| Edit sample | `audio.write(sample,{first=0,frames=n},pcm)` | `audio.write(sample,{0,n},pcm)` |
| Destroy | `gfx.destroy(texture)`, `audio.destroy(sample)` | Same operations with distinct handle types |

Upload options specify `offset_bytes` and `stride_bytes`; omitted or zero stride is the
pixel buffer's row width. Rectangles use top-left coordinates and positive sizes;
uploads must fit the destination. Buffer format must match texture format. Pixel
bytes are row-major index8 or premultiplied RGBA8, in R/G/B/A order. Every RGB
channel must be at most alpha. No texture storage is directly mapped into a game.

PCM is finite interleaved f32, mono or stereo, with a declared source rate from
8,000 to 96,000 Hz. `first` and `frames` address source frames, not bytes or scalar
samples. The buffer's channel count must match the sample. No playback, loop,
resampling or scheduled-edit semantics are implemented by this slice. Sample
creation can omit initial PCM in Luau, or use an empty `PCM_Buffer` in Odin;
storage begins at zero and can be filled with chunked writes.

Luau buffer metadata and handle tokens are frozen; mutate `pixels.bytes` with
the buffer library and `pcm.samples` with `buffer.writef32` at zero-based byte
offsets. Exported `console.Texture`, `Sample`, `PixelBuffer`, and `PCMBuffer`
types support editor checks. Token identity, session and generation are checked
at runtime. Odin exposes `[]u8` pixel bytes and `[]f32` samples; it uses distinct
`gfx.Texture` / `audio.Sample` types. Release game-owned Odin buffers with
`data.free_pixels(&pixels)` / `data.free_pcm(&pcm)` when finished. Luau reclaims
them through GC. Odin callbacks receive the Wasm allocator for ordinary game
allocations; typed buffers retain their originating allocator for release. Guest
allocation remains within the existing memory/heap limits.

Call resource operations inside init/update. Each operation copies supplied data
into bounded SDK staging immediately, so a source buffer can be reused before
the callback returns. Destruction is explicit; handles from a destroyed resource
or previous session fail. Texture/sample definitions are independent in 4a; the
dependency rules for pipelines, readbacks and voices apply when those exist.

For complete, type-checked usage, see the equivalent
[Luau fixture](../tests/resources/cartridges/game.luau) and
[Odin fixture](../tests/resources/cartridges/game.odin). They upload, mutate and
destroy resources, then reuse a slot with a new generation.

## Internal transport and ownership

[resource-transport.json](proposals/resource-transport.json) defines the subset's
version, limits, formats, field layouts, descriptors and configuration exports.
`npm run generate:resources` generates the Odin, Luau and C++ constants;
`node tools/generate-resource-schema.mjs --check` detects stale generated files.
The complete profile's asynchronous mailbox and negotiated configuration records
remain future work; this version uses fixed capabilities and the existing input
arguments, with no asynchronous resource completions.

Before init, the player checks `game_resource_protocol() == 1` and configures a
nonzero fresh session with `game_resource_configure(session)`. The version fixes
the supported operations and limits; a mismatch is rejected. After init and
**every update**, the host calls `game_commit()` then `game_commit_size()`, copies
the packet, validates it in the shared Odin registry, and acknowledges its exact
sequence with `game_commit_ack(sequence)`. There is one sealed packet per guest;
the SDK refuses to reuse its arena before acknowledgement. Draws do not consume
or replay control packets. Legacy guests without these exports remain supported.

The wire header is the proposal's 64-byte `AVP1` header with ABI field 2. Only init
and update phases are implemented; updates require successive ticks and sequences.
Commands begin at byte 64 and use 32-byte records. The payload follows the used
commands immediately. Argument/data offsets are relative to the payload; typed
descriptors contain eight little-endian u32 fields. Destroy has no arguments or
data. Reserved fields are zero. Unknown opcodes, flags, bad ranges, unsupported
formats and malformed descriptors fail the entire packet with a command index.

The registry simulates metadata and prepares copy-on-write allocations before
publication. Failure retains the previous registry, sequence and bytes; temporary
allocations are freed. Accepted mutations reclaim replaced storage after this
synchronous consumer completes. Later asynchronous consumers will require the
retirement tracking specified in the proposal. No guest pointer is retained.

Limits are 1,024 resource slots, 64 MiB runtime resource quota, 16,384 commands and
1 MiB payload per commit. The quota charges live storage, copied packet bytes
and pending replacement allocations, including old/new versions simultaneously.
Fixed registry/staging capacity and allocator overhead are baseline runtime
memory, not claims about RSS. The host input arena and the SDK arena each reserve
at most 1.5 MiB, while empty commits transfer only 64 bytes. Large transfers must
be chunked. Texture axes are 1..1024; actual buffers still must fit guest limits.

The browser runtime now has an 80 MiB linear-memory ceiling to accommodate the
resource quota plus fixed runtime storage and allocation overhead. **Guest memory
remains capped at 8 MiB and the tracked Luau heap at 4 MiB.** The Luau executor's
initial memory grows from 2 MiB to 4 MiB for its bounded transport arena. Native
and browser use the same registry and charging rules. Faults stop the session;
worker errors explicitly release resources and discard the guest.

## Verification

Run `npm run test:resources` on the supported Windows development host. It builds
both SDK fixtures, runs native registry tests and the standalone player, and
compares 121 resource snapshots per language through native and actual browser
Workers. It tests skipped draws, reload, source-buffer reuse, type/generation/
session failures, generation retirement, atomic rollback, copy-on-write budget
exhaustion, malformed packet regions, overflowing ranges, non-finite PCM and
premultiplied-alpha validation. The native registry tests use allocation tracking.
Reports and full traces are written under the ignored `build/resource-verification/`.

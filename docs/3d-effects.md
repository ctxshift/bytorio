# Scene-space effects

The experimental `effects-3d-preview-1` profile uses SDK 0.6.0 (word 1536),
ABI 2, profile 6, resource protocol 8 and feature mask 127. Set both `sdk`
and `profile` in the game manifest. Earlier profile tuples and defaults remain
unchanged; earlier protocols reject effect-material creation.

Both SDKs expose `gfx3d.effect_material(texture, options)`, returning the existing
typed `Material`. It pins an RGBA8 texture and uses ordinary immutable UV meshes
or shared billboard geometry. Creation/destruction require init/update. Texture
uploads own their bytes; particles retain no guest pointers in host resources.

| Option | Luau | Odin | Default |
| --- | --- | --- | --- |
| Blend | `blend = "alpha"` / `"additive"` | `blend = .Alpha` / `.Additive` | Alpha |
| Depth test | `depth_test` | `depth_test` | true |
| Depth write | `depth_write` | `depth_write` | false |
| Address | `address_u`, `address_v` | `address_u`, `address_v` | Clamp |

For Odin, an explicit options literal starts from zero values: include
`depth_test = true` when supplying other options. Omitting the entire options
argument enables depth testing. Luau omitted fields retain the defaults above.

Colors are premultiplied RGBA bytes. Alpha computes source plus destination
times (1 − source alpha), including output alpha. Additive computes saturated
source plus destination, including alpha. Blending occurs in encoded byte color
space; optional SSAA subsequently resolves samples in linear light. Vertex RGB,
flat lighting and fog affect source RGB. Alpha fog approaches fog RGB times
source alpha; additive fog approaches black. Source alpha itself is unchanged.
An alpha-zero fragment can still write depth when explicitly requested.

Depth testing uses strict less-than against the current depth attachment.
Disabling it accepts any clipped fragment; depth writing remains independently
selectable. GPU effects blend only the color attachment. Explicit depth writes
use a separate depth publication for each primitive, preserving ordering even
inside one overlapping mesh. Packed depth bytes are never blended. Depth-write
effects therefore cost additional GPU draws; ordinary smoke should leave writes off.

Draw opaque and cutout geometry first, then alpha effects from far to near, then
the HUD. The caller owns sorting, including interleaved additive effects. Pure
additive effects are commutative until clamping, but mixing blend modes can change
the result. This interface provides no automatic scene sorting or transparent
intersection resolution. Camera/model transforms and clipping use the existing
3D contract. CPU, software SSAA and opt-in GPU/resident execution use the same
materials; CPU stays the default and requires no GPU initialization.

Opcode 75 stores texture, U/V addressing, blend (0 alpha / 1 additive), depth-test
and depth-write booleans, followed by two zero words. It has no payload. Storage
remains a 32-byte material descriptor with format tag 2. All material bounds,
ownership, transaction memory, rollback and committed presentation rules apply.

## Examples and checks

`examples/effects` contains matching gardens with cutout trees, depth-tested
smoke and additive particles. Six shared textures/materials and a 16-slot age
ring bound work; a fixed-size insertion sort orders particles in camera space.
Geometry, texture and material storage is created once, independent of particle
count or lifetime.

```text
mise run //examples/effects:build
mise run //examples/effects:serve
mise run validate //examples/effects:test
mise run validate //examples/effects:test:gpu
```

CPU units assert independently calculated overlap colors, occlusion, depth-write
controls, software SSAA and rollback. Native GL and browser WebGL probes check
overlapping primitives and depth at every sample setting. Gallery replays cover
both SDKs/hosts, both displays, loose/PNG loading, orbit, streamed/resident GPU
geometry, SSAA, mixed 2D/3D and repeated resets. Hardware blending permits one
byte of rounding in independent probes. Cross-host scene comparisons retain
the documented billboard raster tolerance; same-host SDK and CPU comparisons
remain exact. GPU checks require usable hardware and are separate from CPU gates.

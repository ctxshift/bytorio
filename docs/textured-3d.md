# Textured 3D resource contract

The experimental `textured-3d-preview-1` profile uses SDK 0.4.0, profile 4,
ABI 2, resource protocol 6 and feature mask 31. Loaders negotiate the complete
tuple for loose games and PNG cartridges. Existing profiles retain their exact
tuples; protocol 5 does not accept the new resource creation commands.

This contract establishes resource ownership, transport and textured drawing.
Existing colored meshes, cameras, depth,
audio and 2D rendering remain available through this profile. It is not a stable
published profile or a performance guarantee.

## Typed resources

Luau exposes `byt.TexturedMesh` and `byt.Material` through
`byt.gfx3d`; Odin exposes `gfx3d.Textured_Mesh` and `gfx3d.Material` through
`sdk:gfx3d`. These are distinct from colored meshes, voxel volumes and textures.

`textured_mesh(vertices, indices)` snapshots immutable indexed geometry.
Each vertex has three f32 position components, an opaque packed RGBA8 tint and
two f32 normalized texture coordinates. Indices are zero-based u32 triangles.
UVs may be negative or exceed one for tiling, but must be finite and within
[-1024, 1024]. Position, count, upload and shared resource limits retain their
existing compact-3D meanings. Counts do not override the 1 MiB packet limit.

`material(texture, options)` references an existing RGBA8 texture. The host pins
the texture until the material is destroyed. Material destruction does not destroy
the texture. Texture uploads remain allowed and keep their existing snapshot and
rollback semantics. An indexed texture, offscreen target, screen handle, stale
handle or wrong resource kind is rejected. Materials do not copy texture pixels
into separate cartridge-owned storage.

The immutable options select independent U/V address modes: `clamp` or `repeat`
in Luau, `.Clamp` or `.Repeat` in Odin. Both default to clamp. Sampling is nearest
only. Image rows run from top to bottom; UV (0, 0) denotes the top-left texel.
Clamp maps coordinates outside [0, 1] to the edge; repeat uses the fractional
coordinate, including negative inputs. Material alpha is not a blending control.

## Drawing

Both SDKs expose `gfx3d.draw_textured(pass, mesh, material, model)`. The model
defaults to identity. Bind a camera and depth attachment with `gfx3d.bind` first.
This command requires the existing opaque RGBA pass and affine model rules.
UVs and lit vertex tints interpolate with reciprocal clip W after homogeneous
clipping. Nearest sampling selects `floor(coordinate * size)`, bounded to the last
texel; repeat takes the fractional coordinate before selecting a texel. Multiply
sampled RGB by interpolated tint divided by 255, then apply camera fog and round
channels to RGBA8. Textures store premultiplied RGB: this opaque material writes
that RGB with output alpha 255, without unpremultiplication, discard or blending.
Use opaque source textures for ordinary surfaces. Strict less-than depth testing
and depth writes match colored geometry, including equal-depth rejection.

The CPU reference path needs no GPU. Optional CPU quality rendering and native
OpenGL/browser WebGL execution support the same textures with SSAA off, 2× or up
to 1080p. Camera snapping and smooth orthographic presentation follow the existing
compact-3D controls. Perspective cameras do not apply orthographic pixel snapping.
GPU acceleration and resident meshes stay opt-in; neither becomes a cartridge
requirement. If optional staging cannot fit the transaction budget, drawing uses
the reference path and suppresses any incomplete high-resolution preview.

Resident geometry includes immutable UVs and is reused while model/camera matrices
change. Textures have host-assigned versions: an accepted upload creates a new
snapshot identity, while rejected commits retain the previous identity and pixels.
GPU texture copies are reused by version, independently of material address modes.
Native and browser hosts bound the optional texture cache to 32 MiB/1024 entries
and geometry cache to the existing 64 MiB/1024 entries. Cache eviction discards
derived GPU data, never cartridge resources. Reset/reload cannot alias old cache
entries because version identities are never reused within a player instance.

Whole-scene surface sampling continues to apply to its supported colored geometry;
textured meshes use ordinary triangles even when that experimental option is on.
Both SDKs may mix textured and colored draws. Current textured draw boundaries
flush their execution batch, retaining logical color/depth synchronization and
atomic rollback. Removing redundant attachment transfers is a separate optimization.

GPU diagnostics expose `materialUploads`, `materialCacheHits` and
`materialUploadBytes` alongside geometry counters. Browser `materialCacheBytes`
is the texture-cache portion of `textureBytes`; do not add it again to total
texture storage. `cacheBytes` continues to mean geometry buffers only. These are
allocation estimates and uploaded source bytes, not a GPU-driver memory measurement.

Run `mise run validate test:textured3d` for ordinary conformance and
`mise run validate test:textured3d:gpu` on a machine with GPU support for independent
device fixtures and both SDKs at both display resolutions. The hardware gate checks
stationary/moving/edited scenes through native and browser players with each
SSAA/residency setting. It verifies output pixels before checking upload reuse.

Resource construction and destruction occur in init/update callbacks. Use
`gfx3d.destroy` for a material or textured mesh, then the existing texture
destructor after all referencing materials are gone. Shared generation/session
handles, allocation budgets, packet ordering and atomic commit/rollback apply.
Reset releases the complete registry and invalidates old handles.

## Wire layout

The generated resource schema owns these values. A UV mesh vertex occupies
24 bytes: XYZ at offsets 0/4/8, RGBA8 tint at 12 and UV at 16/20. The index buffer
follows the vertices. Opcode 71 creates a textured mesh using the existing
eight-word mesh descriptor. Opcode 72 creates a material with descriptor words
`texture`, `addressU`, `addressV`, followed by five zero words and no data payload.
Address encodings are clamp 0 and repeat 1. Material and textured-mesh kinds are
17 and 18. Both use the existing resource destruction opcode.
Opcode 73 draws a textured mesh; its handle is the mesh, descriptor word zero is
the material handle and all remaining words are zero. The data payload is the
existing 64-byte column-major affine model matrix. Wrong kinds, missing bindings,
stale resources or invalid matrices reject the entire commit.

The host stores one 32-byte immutable material descriptor and pins its texture
through the ordinary registry reference graph. Upload staging and the copied
geometry/descriptor are charged to transaction memory; rejected commands publish
neither new resources nor edits to existing texture data.

# Textured 3D resource contract

The experimental `textured-3d-preview-1` profile uses SDK 0.4.0, profile 4,
ABI 2, resource protocol 6 and feature mask 31. Loaders negotiate the complete
tuple for loose games and PNG cartridges. Existing profiles retain their exact
tuples; protocol 5 does not accept the new resource creation commands.

This initial contract establishes resource ownership and transport. Textured
draw execution is not exposed yet. Existing colored meshes, cameras, depth,
audio and 2D rendering remain available through this profile. It is not a stable
published profile or a performance guarantee.

## Typed resources

Luau exposes `console.TexturedMesh` and `console.Material` through
`console.gfx3d`; Odin exposes `gfx3d.Textured_Mesh` and `gfx3d.Material` through
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
coordinate, including negative inputs. Exact filtering, tint and depth tests
belong to the subsequent draw contract. Material alpha is not a blending control.

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

The host stores one 32-byte immutable material descriptor and pins its texture
through the ordinary registry reference graph. Upload staging and the copied
geometry/descriptor are charged to transaction memory; rejected commands publish
neither new resources nor edits to existing texture data.

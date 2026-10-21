# Depth-tested billboards and alpha cutout

The experimental `alpha-3d-preview-1` profile negotiates SDK 0.5.0 (word 1280),
profile 5, ABI 2, resource protocol 7 and feature mask 63. It retains the existing
resource budgets and all earlier graphics/audio/3D operations. Existing SDK 0.4
and earlier profiles keep their exact tuples and reject the new alpha command.
New projects still default to the stable resource profile; enabling 3D is explicit.

## Material and depth behavior

Both SDKs expose `gfx3d.cutout_material(texture, cutoff, options)`, returning the
existing typed `Material`. Cutoff is an integer byte, defaults to 128 and may be
0 through 255. Address options and texture ownership match
[opaque textured materials](textured-3d.md). Construction/destruction require
init/update; the material pins its RGBA8 texture until destroyed.

Nearest sampling and perspective-correct UVs select a texel. Alpha below the
cutoff discards that fragment before either color or depth writes. Equality
survives. Surviving premultiplied RGB is unpremultiplied using the sampled alpha,
then multiplied by vertex tint/lighting and fogged. The output is opaque. At
cutoff zero an alpha-zero texel survives as opaque black. There is no blending
in this material; transparent effects are a separate API. Opaque materials keep
their original premultiplied-RGB behavior.

Strict less-than depth testing still applies. Rejected foreground texels leave
the underlying color and depth intact, so drawing farther geometry afterward
fills holes. Offscreen targets cannot be material sources, preventing feedback.
Resource snapshots, rollback, generation handles, versioned GPU texture caches
and optional CPU/GPU quality settings retain their existing guarantees.

Opcode 74 creates a cutout material. Descriptor words are texture handle,
U address mode, V address mode, alpha cutoff and four zero words; there is no
data payload. Material storage remains a 32-byte descriptor and its resource
kind remains 17. The registry's material format tag is cutout 1, opaque 0.
The schema generates these encodings. Draws use the existing opcode 73.

## Billboard geometry and transforms

`gfx3d.billboard()` creates one immutable `TexturedMesh`: a unit XY quad with
opaque white tint and top-left texture orientation. Create it once during init
and share it across actors. It uses ordinary mesh/index budgets, resource
ownership and destruction; there is no second billboard renderer or per-frame
geometry upload requirement.

`gfx3d.draw_billboard(pass, quad, material, desc)` draws through the ordinary
textured mesh path. `gfx3d.billboard_model(desc)` exposes the same affine model
for callers that want to issue the draw themselves. The descriptor contains:

| Field | Meaning |
| --- | --- |
| `position` | World-space anchor, three components |
| `size` | Positive width/height in world units |
| `pivot` | Normalized local XY anchor; defaults to (0,0), bottom-left |
| `view` | Affine world-to-camera view, without projection; normally `look_at` |
| `mode` | Luau `"facing"` / `"upright"`, Odin `.Facing` / `.Upright`; defaults to facing |
| `rotation` | Optional in-plane rotation in radians; defaults to zero |

Use pivot (0.5,0) for centered feet, (0.5,0.5) for centered icons. Facing mode
uses the camera's right/up basis; upright mode projects camera right onto world
XZ and uses world Y as up. Explicit in-plane rotation is applied afterward.
Provide a rigid view matrix. Degenerate bases, projected views, nonfinite input
and nonpositive sizes are rejected. Ordinary model-coordinate bounds still apply.

Keep the unprojected view alongside the camera's combined view-projection matrix.
Changing the view, position or size changes uniforms, not quad geometry or texture
identity. Billboard geometry follows scene depth; HUD sprites remain ordinary 2D
draws after the 3D scene. The helpers do not perform sorting or lighting overrides.
The Luau bundler includes the billboard math module only for the alpha preview
profile. Earlier profiles retain their existing source ceiling and report an
explicit error if a game calls the newer transform helper.

## Examples and verification

[Luau](../examples/billboards-luau/main.luau) and
[Odin](../examples/billboards-odin/main.odin) render matching perspective gardens.
Trees and fences remain upright during orbit; the item faces the camera and the
kart occludes artwork through ordinary depth. The examples precreate 32 view/camera
pairs and reuse them, so orbit does not rebuild geometry or resources.

The simple shadow recipe reuses the quad with a circular dark cutout texture,
rotates its plane onto world XZ, scales it under the kart and offsets it slightly
above the track to avoid depth ties. It is an opaque art decal, without shadow maps.

```text
mise run build:billboards
mise run serve:billboards
```

Open the printed local URL and choose a player. Native executables are in
`build/billboards/odin/build/native` and `build/billboards/luau/build/native`.
Left/right arrows select orbit views; Action chooses 640×360 instead of 320×180.
The players default to CPU rendering. GPU, resident meshes and SSAA remain opt-in.

Run `mise run validate test:billboards` for native/browser CPU conformance and
`mise run validate test:billboards:gpu` for the hardware execution matrix.
Independent fixtures check pivot transforms, upright axes, exact cutoff boundaries,
UV orientation, clipped quads, depth holes and preserved older profiles; scene
comparisons additionally check both SDKs, PNG/loose loading, orbit and both displays.
CPU and same-host SDK frame hashes must match exactly. GPU comparisons between
native GL and browser WebGL retain captures for any differing frame and allow
at most 16 differing pixels at 320×180 (64 at 640×360), with a maximum byte-channel
delta of 32. This bounds driver differences in perspective rasterization;
independent alpha-threshold and depth fixtures still require exact expected values.

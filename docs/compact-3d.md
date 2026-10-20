# Compact 3D and voxel prototype

Milestone 4f implements an experimental software rendering foundation shared by
the standalone native player and browser player. Both SDKs expose indexed meshes,
explicit cameras, depth attachments and cached voxel surfaces. This is an original
implementation using the existing resource ownership and transaction machinery.

The separate [voxel resolution study](../experiments/voxel-resolution/README.md)
preserves a procedural winter scene for comparing visual detail at three output
sizes. It uses an independent renderer and does not extend the console profile.

## Configurable GPU execution

The player now has an opt-in GPU 3D raster path: OpenGL 3.3 in the standalone
native runtime and WebGL 2 on an OffscreenCanvas in the browser Worker. The
native player remains an Odin executable without a webview. The GPU adapters
compile the same shader bodies from `runtime/odin/gpu/`. Both Luau and Odin
cartridges use the existing mesh/camera/depth APIs and resource transport.

CPU remains the default reference renderer. Browser graphics settings select
**CPU reference**, **GPU 3D + CPU 2D**, or **Auto**, with supersampling off,
up to 2× per axis, or up to 1080p, orthographic camera snapping and smooth pan
presentation. Preferences persist in browser storage when available; applying
them restarts the game. URL flags override stored settings, for example:

```text
player.html?renderer=gpu&ssaa=1080p&smooth-pan
player.html?renderer=cpu
```

Native equivalents, from an exported game's native directory:

```text
./player.exe --renderer gpu --ssaa 1080p --smooth-pan
./player.exe --renderer gpu --ssaa 2x --pixel-snap
./player.exe --renderer cpu
./player.exe --renderer auto
```

Smooth panning implies camera snapping. GPU quality options require the GPU
path; explicit CPU/quality conflicts are rejected. Auto chooses at startup and
falls back to CPU if device initialization is unavailable. Explicit GPU mode
reports failure instead. Device failure during a draw rejects the transaction;
it does not publish partial attachments or silently change devices mid-packet.
The stable resource-av profile continues using its existing CPU 2D semantics.

### Execution and ownership

The common Odin resource implementation still validates handles, phases,
matrices, palettes, clipping and logical work limits. It transforms and lights
triangles into bounded, host-owned staging. Consecutive 3D draws are batched;
before a pass/state change or 2D operation, the GPU rasterizes the batch into
private scratch color/depth targets. Color and packed f32 depth are read back
into transaction-owned attachments. CPU 2D composition and resource readbacks
then observe that completed batch. Only the existing successful commit publishes
attachments and presentation data. Rollback frees temporary staging and keeps
the previous output and presentation snapshot. Session reset preserves the
host's selected device, not GPU image contents.

Triangle staging counts against transaction memory. If it cannot fit, that batch
uses the CPU rasterizer. GPU scratch textures are device-owned and reused by
shape, never guest pointers or cartridge handles. Sample counts are capped at
six per axis and internal dimensions at approximately 1920×1080, plus the
bounded overscan border. Larger offscreen targets can reduce the requested
sample factor to fit. Optional screen presentation storage is separate from the
cartridge resource budget: two screen-sized color/mask snapshots may coexist
during commit, and the host presenter retains at most one 1920×1080 RGBA image.

This first backend deliberately retains CPU transforms/lighting, logical
bounding-box work accounting, 2D composition and GPU readback barriers. It is
not the GPU-resident renderer used in the independent riverside experiment.
No 60 fps guarantee for that scene follows from this integration. The next
performance step is cached GPU mesh uploads and GPU-resident render targets,
with explicit synchronization at actual CPU readback boundaries.

### Quality and presentation semantics

GPU SSAA rasterizes 3D at the selected integer sample factor and resolves color
in linear light, including premultiplied alpha/coverage. Depth resolves to the
nearest covered sample. A later batch uses logical depth again, so partially
covered edge pixels can conservatively occlude later batches. Offscreen
composition, clipping and CPU readbacks remain supported, with GPU device/quality
dependent pixels. CPU conformance remains the exact coverage/color reference;
the experimental 3D profile does not promise identical GPU pixels across every
driver. Gameplay should not depend on cross-device equality of GPU pixel reads.

Camera snapping rounds only the translation in an orthographic view-projection
matrix to the game's output pixel pitch. Perspective cameras are not snapped;
game state and model positions remain continuous. SSAA does not change the
cartridge's two logical display modes or resource dimensions.

Smooth presentation applies to an enlarged, single screen 3D batch with a full
viewport and orthographic camera. It renders a one-game-pixel overscan border,
then presents nearest-sampled blocks at an integer scale using the remaining
camera offset, rounded to presentation pixels. Opaque CPU HUD draws after that
batch stay fixed on the game grid; a separate coverage mask tracks them even
when their colors match the world. Multiple screen batches, partial viewports,
perspective, later screen clears, translucent/custom-blend overlays, offscreen
presentation and a 1× display use ordinary logical presentation instead. The
browser reports when smooth presentation is inactive. Rotation still changes
projected geometry; this feature stabilizes panning, not rotational silhouettes.
Input coordinates and framebuffer hashes remain in logical game pixels.

Run `mise run test:gpu` on a Windows machine with OpenGL 3.3 and installed Chrome
for the opt-in hardware checks. They exercise both SDKs, native/browser hashes,
independent color/depth/coverage fixtures, rollback, 2D ordering, HUD stability,
display switches, settings restarts and unavailable-device fallback. Reports
are retained under `build/gpu-validation/`. CPU profile gates remain independent
of hardware GPU availability.

## Profile and compatibility

Opt in with SDK `0.3.0` and profile `compact-3d-preview-1` in `console.json`.
The exact tuple is profile 3, ABI 2, SDK word 768, resource protocol 5 and feature
mask 15. Bit 8 adds compact 3D to the three existing resource features. Native and
browser loaders validate the complete tuple before game callbacks, including PNG
metadata. Loose payloads and PNG cartridges use the same negotiation.

The default remains SDK 0.2.0 / `resource-av-1`. That published profile still
negotiates protocol 4 and mask 7; its limits and opcode meanings are unchanged.
The shared protocol schema's `version` is the highest supported experimental
version, while `stableVersion` identifies the published version. Protocols below
5 reject 3D commands. ABI 1 games retain their compatibility path.

See the [experimental profile](../sdk/profiles/compact-3d-preview-1.json) and
[wire schema](../sdk/resource-protocol.json). The preview retains the 64 MiB
resource budget, 8 MiB guest memory, 4 MiB Luau heap and 1 MiB commit payload.
PNG cartridges remain capped at 2 MiB. Large asset streaming is still milestone 5.

## SDK surface

Luau uses `console.gfx3d`; Odin imports `sdk:gfx3d`. The SDKs expose equivalent
resource operations:

| Operation | Inputs / result |
| --- | --- |
| `mesh` | Vertex positions/colors plus zero-based triangle indices → `Mesh` |
| `depth` | Width and height → `Depth` attachment |
| `camera` | View-projection, light, ambient and fog → immutable `Camera` |
| `voxel` | Dimensions, palette and dense indexed cells → `Voxel` |
| `edit` | Volume, origin, extent and replacement cells |
| `bind` | Existing graphics pass, depth, camera and clear-depth flag |
| `draw` | Pass, mesh or volume, affine model matrix |
| `destroy` | Explicit resource destruction, with stale/reference checks |

Math helpers include `identity`, `multiply`, `pose`, `look_at`, `orthographic`
and `perspective`. Odin's `camera_defaults(view)` supplies unlit/no-fog defaults;
Luau's optional camera controls use the same defaults. These helpers round matrix
elements to f32 before transport. Camera replacement is explicit: create a new
resource and release the old one in an init/update transaction.

Meshes are immutable and uploaded in a single commit. Vertex/index count ceilings
also intersect with the 1 MiB packet payload cap; the maximum counts cannot all
be uploaded together. Split larger geometry across resources until a future
incremental asset-loading contract supports it.

A minimal draw inside a cartridge callback, after creating resources:

```luau
local pass = console.gfx.begin_pass(console.gfx.screen(), {
    clear = true,
    color = console.rgb(20, 24, 32),
})
console.gfx3d.bind(pass, depth, camera)
console.gfx3d.draw(pass, mesh, console.gfx3d.identity())
console.gfx.end_pass(pass)
console.gfx.present(console.gfx.screen())
```

```odin
pass := gfx.begin_pass(gfx.screen(), {clear = true, color = 0xff201814})
gfx3d.bind(pass, depth, camera)
gfx3d.draw(pass, mesh, gfx3d.identity())
gfx.end_pass(pass)
gfx.present(gfx.screen())
```

Draw 2D sprites/text in the same pass for a HUD, or render 3D into an offscreen
RGBA target and compose it through the existing 2D passes. A depth attachment
must match its color target's dimensions. There may be eight depth attachments,
separately from the eight offscreen color targets, within the shared memory budget.

## Rendering semantics

- Matrices are column-major, acting on column vectors. View space is left-handed;
  homogeneous clipping uses `-w ≤ x,y ≤ w` and `0 ≤ z ≤ w`. `look_at` uses world
  +Y as up and rejects a zero or vertical direction. Perspective FOV is in radians.
- A vertex contains three f32 coordinates and one opaque packed RGBA8 color.
  Indices are u32 and zero-based in both SDKs. Resource positions and matrix
  coefficients must be finite, with magnitude at most 10,000. Models must be
  affine, with final row `[0, 0, 0, 1]`.
- Triangles are clipped against all six homogeneous planes before perspective
  division. Coverage uses a top-left rule and coordinates quantized to 1/256 pixel.
  Color interpolation is perspective-correct. Degenerate triangles and vertices
  too close to zero homogeneous w are discarded.
- Depth is f32 normalized device depth. Creation and requested clears initialize
  it to 1; strict less-than wins, so equal quantized depths preserve the earlier
  draw. Both triangle orientations render; there is no backface culling control.
- Flat diffuse lighting uses transformed face normals and the supplied light
  vector, clamped to [0, 1], combined with ambient gain in [0, 1]. Each light
  component is bounded to [-1, 1]. Supply a unit vector for directional lighting;
  ambient 1 disables it. Fog linearly mixes RGB using normalized device depth,
  with explicit start/end bounds between 0 and 2. Start 1/end 2 disables visible fog.
- The initial 3D path requires the default opaque RGBA pipeline and no stencil
  attachment. It honors the pass scissor. The 2D affine transform affects 2D
  commands; 3D uses its explicit model and camera matrices. Textures, transparent
  meshes, custom shaders and shadows are not implemented.

## Voxel storage and edits

Cells are one-byte palette indices, X changing fastest, then Y, then Z. Zero is
empty. Occupied entries must resolve to opaque palette colors. Occupancy does not
change with palette alpha. Invalid palette edits that would make occupied cells
transparent are rejected; RGB changes reuse cached geometry. A live volume pins
its palette until the volume is destroyed.

The host culls interior faces and stores an indexed quad surface alongside the
source grid in one versioned allocation. Instances share this cache. The prototype
does not merge coplanar faces or perform chunk-local remeshing: a region edit
rebuilds the bounded volume synchronously. This makes edit cost measurable without
introducing asynchronous resource visibility. Models can be animated by selecting
prebuilt frame resources and transforming instances.

Source cells, generated geometry, depth, staging, previous versions and edit
scratch all count against transaction memory. Resource updates, their derived
surfaces and rendered color/depth publish atomically; failed commits preserve the
previous visible data. CPU/GPU execution is not shared with guest pointers.

Prototype bounds are 32 cells per volume axis, 16,384 exposed faces per volume,
65,536 mesh vertices, 98,304 mesh indices, 65,536 submitted triangles per commit,
131,072 source cells rebuilt per commit and 16,777,216 charged pixel operations.
Bounding-box raster visits, target clears and depth clears consume pixel work.
Palette validation also bounds inspected voxel cells. These are rejection bounds,
not frame-time guarantees. They remain provisional pending device qualification.

## Protocol additions

All new descriptors contain eight u32 words, with unused words zero. Existing
transaction phases, session/generation handles and canonical payload ranges apply.
New controls run in init/update; bindings/draws run inside a draw pass.

| Opcode | Primary handle | Descriptor words | Data |
| --- | --- | --- | --- |
| 64 create mesh | New mesh | vertex count, index count | 16-byte vertices followed by u32 indices |
| 65 create depth | New depth | width, height | None |
| 66 create camera | New camera | All zero | 96-byte camera |
| 67 create volume | New volume | width, height, depth, palette | Dense cells |
| 68 edit volume | Volume | x, y, z, width, height, depth | Dense replacement region |
| 69 bind 3D | Depth | camera, clear-depth boolean | None |
| 70 draw mesh/volume | Mesh or volume | All zero | 64-byte model matrix |

Camera bytes contain the 64-byte view-projection matrix, light XYZ at byte 64,
ambient at 76, packed fog color at 80, fog start/end at 84/88 and zero padding
at 92. All numeric components except packed color/padding are f32. Multibyte
values are little-endian. Ordinary resource destruction releases the new kinds.

## Build, run and measure

From the repository root:

```text
mise run build:3d
mise exec -- node tools/serve.mjs build/compact-3d
```

Open `/player.html` for both cartridges side by side, or
`/odin/build/web/player.html?game=./game.png` and
`/luau/build/web/player.html?game=./game.png` on the printed server address.
Run `build/compact-3d/odin/build/native/player.exe` or the matching `luau` executable
for the standalone native demos. Each distribution includes its PNG cartridge.

Down edits a wall cell, Up adds a checkerboard volume, Left draws 64 shared props,
Right selects perspective, and Action (Space) selects 640×360 while held. Default
rendering is 320×180. The character animates and the foreground prop rotates.

`mise run test:3d` runs focused ownership/raster tests, builds both cartridges,
loads PNGs in the standalone and interactive browser players, and compares exact
frame hashes through native and browser Workers for ten workload/resolution pairs.
It benchmarks five measured passes following two warm-up passes and retains raw
samples, screenshots, load observations and resource accounting in
`build/compact-3d/`. It is part of `mise run test` and the CI artifact export.

CPU measurements exclude display/audio output; browser pixel-copy time is recorded
separately. Edit/update time includes guest work, transport, validation, copies and
surface rebuilding, not just the mesher. Native process working set, browser/guest
linear memory and resource-budget bytes describe different things. No full audio
DSP stress workload is included in this 3D benchmark.

See [measurements](compact-3d-measurements.md) for observed results and remaining
work. Physics, streaming, a scene editor and a GPU backend are separate extensions.

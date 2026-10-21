# Sunline Sprint original assets

These small, original meshes were authored for this example. The red kart,
purple-haired driver, folded cape, leafy trees and hilltop keep follow the
grassland art direction in `generated/concepts/bytorio_kart/`. No third-party
model, texture or character data is included.

The editable workshop source is [`../tools/assets.mjs`](../tools/assets.mjs).
It exports `generateAssets()` for the example's mise build/generation tasks.
The checked `.gltf` files are standard glTF 2.0 artist inputs and may also be
edited in a glTF-capable modeling tool. Regeneration replaces those edits, so
either keep changes in the workshop source or intentionally adopt the edited
glTF as the new source. The asset generator does not write SDK modules.

Import the checked model using the regular SDK pipeline:

```text
mise run byt -- import examples/kart3d/assets/kart-lod.gltf --output examples/kart3d/build/imported/kart
```

The other `.gltf` files use the same command with a dedicated output directory.
`kart-low.gltf` and `kart-high.gltf` are complete standalone artist models with
identical named nodes and pivots. `kart-lod.gltf` stores their shared parts once
for runtime selection. Load one of these three inputs, according to the game’s
needs; the combined asset does not require loading the standalone variants.
Each source references the adjacent `atlas.png`, a 16×16 opaque RGBA8 texture.
It uses nearest sampling and clamp addressing. There are no extensions, skins,
animation tracks or lighting dependencies. All assets require the existing
SDK 0.4.0 `textured-3d-preview-1` profile or a compatible later profile.

## Scale and animation

After import, +Y is up, +Z is forward and X spans the axle. The root sits on the
road plane at Y=0. Source glTF Z is reflected by the workshop writer because
the importer restores the console coordinate convention. The wheel radius is
0.390625 units; the chassis is roughly 2.4 units long and the driver reaches
2.4375 units high. The cape trails to Z=-1.796875. No global rescaling is needed
for the existing course.

| Node | Parent | Imported local translation | Purpose |
| --- | --- | --- | --- |
| `body` | root | 0, 0, 0 | Chassis, seat, engine, hood, exhausts and bumpers |
| `driver` | `body` | 0, 0, 0 | Torso, arms, steering bar, head and sculpted hair |
| `cape` | `driver` | 0, 1.34375, -0.4375 | Neck pivot for rigid cape motion |
| `wheel_front_left` | `body` | -0.890625, 0.390625, 0.71875 | Steering and axle rotation |
| `wheel_front_right` | `body` | 0.890625, 0.390625, 0.71875 | Steering and axle rotation |
| `wheel_rear_left` | `body` | -0.9375, 0.390625, -0.765625 | Axle rotation |
| `wheel_rear_right` | `body` | 0.9375, 0.390625, -0.765625 | Axle rotation |

All four wheel nodes share one mesh. Multiply each bind transform by a local
rotation to retain its pivot. Rotate the wheels around X to roll and the front
wheels around Y to steer. The cape is a separate five-triangle folded surface;
a small Y rotation adds motion without rebuilding geometry. Driver geometry
uses the kart origin, so a small Y rotation turns its silhouette around the
seat; the cape inherits that rotation.

## Runtime quality selection

The high model adds cooling fins, a seat hoop, side rails, bumper guards, an
open steering rim, gloves, eyes, extra hair locks and sixteen-sided wheels.
The low model keeps the same silhouette and uses eight-sided wheels. This is
a geometry choice independent of CPU/GPU rendering; either host can draw either
version.

The combined asset contains the seven animation nodes above plus three detached
resource nodes: `body_detail`, `driver_detail` and `wheel_high`. The detached
nodes identify additional mesh resources; their identity matrices do not define
where those details should be drawn. The game draws them using the animated
body, driver and wheel transforms already calculated for the corresponding
base parts. Use the generated instance's meshes and material with
`draw_textured` to select the required parts; calling the generic model `draw`
function would render every node, including the detached alternatives.

| Primitive index (Odin / Luau) | Geometry | Low quality | High quality |
| --- | --- | --- | --- |
| 0 / 1 | Body | once at body transform | once at body transform |
| 1 / 2 | Driver | once at driver transform | once at driver transform |
| 2 / 3 | Cape | once at cape transform | once at cape transform |
| 3 / 4 | Eight-sided wheel | once at each wheel transform | omitted |
| 4 / 5 | Body details | omitted | once at body transform |
| 5 / 6 | Driver details | omitted | once at driver transform |
| 6 / 7 | Sixteen-sided wheel | omitted | once at each wheel transform |

All primitives use material index 0 in Odin or 1 in Luau. The low selection is
seven draws and 314 triangles; the high selection is nine draws and 600
triangles. A distance rule, host preference or player option can select quality
without creating resources again. Keep cape/steering/rolling transforms common
to both selections so switching quality does not move animated parts.

Create one resource instance per imported asset and reuse it for repeated
draws. Independent transforms do not require independent resource instances.
The one-node scenery assets have their base at Y=0: `tree` is about 4.23 units
tall, `castle` is 15.2 units tall and 11.3 units wide, and `roadside` is a
0.95-unit rock and wildflower cluster.

## Resource costs

Counts below are measured through the existing importer, including its
normalized vertex/index representation and the atlas upload. Generated source
sizes include the standard formatters. These are asset costs, not a scene
triangle cap or a performance measurement.

| Asset | Unique vertices | Unique triangles | Triangles per draw of the complete model | Meshes / draws | Upload bytes | Luau / Odin source bytes |
| --- | ---: | ---: | ---: | --- | ---: | ---: |
| Kart low | 259 | 218 | 314 | 4 / 7 | 9,888 | 39,344 / 43,175 |
| Kart high | 445 | 408 | 600 | 4 / 7 | 16,632 | 61,952 / 64,063 |
| Kart LOD collection | 495 | 440 | 314 or 600 selected | 7 / 7 or 9 selected | 18,216 | 66,932 / 69,260 |
| Tree | 41 | 44 | 44 | 1 / 1 | 2,568 | 15,265 / 19,732 |
| Castle | 155 | 88 | 88 | 1 / 1 | 5,832 | 24,990 / 29,272 |
| Roadside | 42 | 22 | 22 | 1 / 1 | 2,328 | 14,272 / 19,005 |

Each imported module owns one texture and one material. Loading several modules
duplicates the 1,024-byte atlas, while repeated draws of the same instance share
it. All generated modules remain below the importer source-size bound. The game
still needs to fit its complete SDK, source, commands and resources within its
selected profile.

The atlas tiles, in row order, are red paint, shaded red, charcoal, steel, tire
tread, purple, shaded purple, skin, ivory, gold, light foliage, dark foliage,
bark, masonry, wheel hub and asphalt. Tiles are 4×4 texels; UVs stay inside each
tile to prevent nearest-sampling seams. Painted solid faces sample a tile's
center and share indexed vertices; tire, hub, stone, bark and asphalt surfaces
use UV patterns. The base-color/flat-normal import path provides the final
runtime lighting.

# Voxel resolution study

Two independent scenes compare the same geometry at 320 × 180, 640 × 360 and
1920 × 1080. The build task renders both; the comparison pages link to each other.

## Winter diorama

Preserved procedural winter diorama: a bundled character, fox, snow-covered
bench, bare tree, and enlarged snowman on the front-right drift. All snow uses
one base color; directional lighting, shadows and local occlusion produce its
shading. Broad drifts, a raised right bank and a lower winding path shape the
terrain. There is no mailbox. Its source is `render.mjs` and `index.html`.

## Riverside world

`river.mjs` and `river.html` recreate a cottage, fenced lawn, leafy tree,
irregular oval cobbles, humanoid rabbit adventurer and arched red bridge over a
stream. Curving banks step down to the water, hills vary in height and ragged
grass lips overhang exposed soil. The rabbit has long ears, a pale muzzle and a
tail, with a tunic, sword and shield. The scene fills
the viewport, with no scoreboard or exposed platform boundary. Terrain is
evaluated procedurally at world X/Z coordinates beyond the camera; a bounded
cache stores only the placed props, not the world terrain. The camera sees a
window into that terrain rather than an isolated volume. Every output pixel
must intersect scene geometry or terrain; CPU generation asserts this independently
at each resolution. This does not implement chunk streaming in the console.

The interactive page uses `river-live.js`, a standalone WebGL 2 viewer. The
build also calls `river-mesh.mjs` to bake the same voxel surfaces and per-face
lighting into separate world and rabbit meshes. A 320 × 320-cell terrain patch
extends beyond all allowed camera views; walking and camera panning are bounded
to keep its edges out of view. This live mesh is not an infinite streamed world.

## Interactive supersampling comparison

Select 320 × 180 or 640 × 360 and toggle **Supersampling from 1080p**. Direct mode
renders one sample per output pixel. Supersampling renders the identical scene
and camera into a 1920 × 1080 color/depth target, then averages each 6 × 6 or
3 × 3 block in linear color space before encoding the final image to sRGB.
Both modes produce a canvas at the selected output resolution, with nearest
sampling for final enlargement. WebGL context antialiasing is disabled, so the
direct comparison does not include hidden hardware MSAA. At 1920 × 1080 there
is no downsampling, and the supersampling control is disabled.

Click the view to focus it. **WASD** walks and turns the rabbit, with basic terrain,
water and obstacle collision. **Arrow keys** pan the camera. **Follow rabbit**
tracks movement, and **Gentle camera motion** adds a repeatable fractional pan.
**Pause motion** freezes rabbit and camera movement while quality and resolution
controls remain active. **Reset position and camera** restores the starting pose.
Losing focus clears held keys.

Lighting, shadows and local occlusion are baked into mesh face colors. The
rabbit moves independently, but its lighting and world shadows are not updated
dynamically. Scene colors use a linear RGBA8 intermediate target, so this is not
an HDR-quality rendering pipeline. The original CPU PNGs and detail crops remain
available as static references rather than screenshots of the interactive view.

Its page is generated at `build/compact-3d/resolution/river/index.html`, or
`http://127.0.0.1:8081/resolution/river/index.html` on the existing demo server.

## Regenerate and view

From the repository root:

```sh
mise run build:voxel-resolution
mise run serve:voxel-resolution
# Verify GPU filtering, output sizes and movement controls:
mise run test:voxel-resolution
```

Open the printed player URL, or `http://127.0.0.1:8080/index.html` with the
default port. Set `PORT` to select another port. When the existing 3D demo server
is running on port 8081, the same generated page remains available at
`http://127.0.0.1:8081/resolution/index.html`.

The source files in this directory are the canonical scene and comparison page.
The task regenerates PNGs, live meshes, browser code, the page and a diagnostic report under the ignored
`build/compact-3d/resolution/` directory. No reference image or external code is
required to regenerate the scene. Rendered images are generated artifacts and
are not committed.

The winter images use the same 144 × 100 × 144 voxel grid, orthographic camera,
lighting and deterministic snow particles. The riverside images share their
procedural world, props, camera and lighting. Output sizes are 320 × 180,
640 × 360 and 1920 × 1080, with one center ray per pixel and no antialiasing.
The first two are also enlarged 6× and 3× with nearest sampling for an equal-size
1920 × 1080 comparison. Fixed-size detail crops preserve these exact scales;
fit-to-window presentation can introduce additional fractional scaling.

The riverside page also offers **Native size (no enlargement)**. This displays the
live canvas at its intrinsic output dimensions:
320 × 180, 640 × 360 or 1920 × 1080 CSS pixels. A readout lists the render size,
internal scene dimensions, final canvas dimensions and displayed size. Native size and the enlarged
1920-pixel presentation are mutually exclusive. Browser zoom and high-DPI
screens can map a CSS pixel to multiple physical device pixels; this control
does not change the generated image resolution.

These are standalone CPU/GPU experiments for evaluating visual style. They do
not run through either cartridge SDK or the console renderer. Their shadows and
local face occlusion are not evidence of implemented console API support, and
1080p is not a new console display mode. Timings in `report.json` include image
generation and are not console benchmarks. The live viewer helps assess motion
shimmer, but does not qualify console GPU performance or promise a frame rate.

The browser verifier checks all five effective resolution/quality combinations,
native dimensions, complete frame coverage, fixed-pose toggling, movement,
camera controls and focus/pause/reset behavior. It independently recomputes
filtered scene pixels and tests a synthetic black/white texture: the even mix
must resolve to approximately 188 in sRGB rather than 128. Results and captures
are retained in `build/compact-3d/resolution/river/live-checks.json` and adjacent
PNGs. Automated browser execution may use a software graphics driver; these
checks establish correctness, not hardware performance.

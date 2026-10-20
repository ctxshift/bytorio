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
lighting into separate world and rabbit meshes. A 384 × 384-cell terrain patch
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
water and obstacle collision. **Arrow keys** pan the camera and **Q/E** orbit it.
**Rotate camera** continuously orbits the view. **Follow rabbit**
tracks movement, and **Gentle camera motion** adds a repeatable fractional pan.
**Pause motion** freezes rabbit and camera movement while quality and resolution
controls remain active. **Reset position and camera** restores the starting pose.
Losing focus clears held keys.

The **Rendering mode** selector adds two stabilization comparisons alongside
the original continuous 3D path:

- **Pixel-snapped 3D:** quantizes projected camera and rabbit translations to the
  final output grid, in the camera's right/up basis. Simulation positions remain
  continuous. With fixed view angle, fractional translations within the same
  snap interval do not change the rendered pixels. The 1080p supersampling
  checkbox remains available; snapping always uses the final output pixel size.
- **Rabbit sprite:** uses the snapped world camera and captures the rabbit into
  an independent, fixed-pivot color/depth image. Its local capture always uses
  1080p-equivalent sample density, averaged to the output pixel pitch. Translation
  reuses exactly the same filtered image and places it at integer pixel coordinates.
  The single-entry capture cache refreshes when facing, view angle or output
  resolution changes, so it stays bounded during orbiting. Supersampling controls
  the background in this mode.

The sprite stores premultiplied linear color and fractional coverage. Compositing
happens in linear space before sRGB encoding. Per-pixel depth is compared against
the world, so the sprite can pass behind geometry. Depth uses the nearest covered
sample in both images; this is conservative around subpixel occluders, not exact
per-sample transparency/intersection handling. The sprite is not a flat overlay.

These modes target translation stability. Orbiting the camera or turning the
rabbit changes the projected shapes and can still change pixel clusters. They
do not reproduce an undisclosed external renderer. The separate
[rotation research note](../../docs/rotating-pixel-art-research.md) evaluates
persistent surface sampling and its limitations.

**Smooth pan presentation** is independent of these modes and available for
snapped, sprite and surface rendering. It renders one extra game pixel on each
edge, resolves at the chosen game pixel pitch, then nearest-samples into an
integer-scale presentation canvas. The residual camera translation is rounded
to presentation pixels. The integer scale follows the displayed device-pixel
width, capped at 6; resizing can change the scale. Native-size view disables
it, and the actual-1920 presentation gives integer CSS enlargement at normal
browser zoom. Fractional CSS fitting can still introduce uneven screen blocks.
It adds presentation resolution, not 3D scene detail or a console display mode.
At scale 1 it has no finer motion steps. Camera rotation still changes geometry.
At a camera snap boundary the scene is re-rasterized: rare edge or depth ties
can change even though the presentation pass itself is an exact nearest copy.

**Rabbit surface samples (experimental)** replaces only the rabbit mesh with
fixed object-local samples, spaced at 0.25 world units on every exposed voxel
face. Each array record is a persistent sample identity containing a position,
normal and baked face color. This array and its GPU buffer are uploaded once;
camera and actor rotations only transform the samples. Back-facing samples are
rejected, projected centers snap to the game grid, and screen-aligned square
splats depth-test against the world and each other. SSAA filters the result at
the same output pitch. The world remains the ordinary triangle mesh.

This isolates persistent color/sample identity from changing view visibility.
It is not a guarantee of stable silhouettes or identical pixels through rotation:
square footprints overlap, may leave gaps, inflate silhouettes, and approximate
surface depth with center depth. Equal-depth overlaps use fixed draw order;
grazing angles can change visible samples abruptly. Baked face colors do not
exercise fine textures or dynamic lighting, so this scene alone cannot establish
how much stability improves on more detailed assets. No temporal filtering or
view-angle cache is involved. Use Q/E and WASD to compare the modes.

**Whole-scene surface samples (experimental)** also replaces the static world
mesh with a persistent world-space sample cloud. Terrain, water, cottage, tree,
bridge, fences and cobbles all use the same square-splat renderer as the rabbit.
The world spacing is 0.5 units, versus 0.25 for the rabbit, to limit storage and
overdraw. The world has 682,064 samples (23.4 MiB of records on each of the CPU
and GPU, excluding meshes, textures, driver overhead and temporary generation
allocations). Generation allocates one typed record array instead of a large
intermediate JavaScript number array. The cloud is created on first selection;
switching resolutions, rotating and switching modes reuse it. No view-dependent
resampling or world triangle fallback is used. Existing modes remain unchanged.

Use **Rotate camera** or Q/E to compare this mode against **Rabbit surface
samples**, **Pixel-snapped 3D** and **Continuous 3D**, with matching resolution
and supersampling. Smooth pan presentation also works with the sampled world.
The sample positions and baked colors stay fixed, but projected placement,
coverage and visibility change. Expect more obvious silhouette and depth
artifacts on fine scenery than in the rabbit-only experiment. This is a visual
prototype, not evidence of a frame-rate target or a console memory budget.

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

The browser verifiers check five continuous and ten stabilized resolution/quality combinations,
native dimensions, complete frame coverage, fixed-pose toggling, movement,
camera controls and focus/pause/reset behavior. It independently recomputes
filtered scene pixels and tests a synthetic black/white texture: the even mix
must resolve to approximately 188 in sRGB rather than 128. Results and captures
are retained in `build/compact-3d/resolution/river/live-checks.json` and adjacent
PNGs. Automated browser execution may use a software graphics driver; these
checks establish correctness, not hardware performance.

`stability-checks.json` additionally retains pixel-grid invariance, bit-identical
sprite reuse during translation, recapture on view/facing changes, fractional
coverage, full-turn frame coverage and Q/E controls. Independent red/green depth
fixtures check front/behind occlusion against known results.

`presentation-checks.json` records exact one-presentation-pixel horizontal and vertical motion
in all four snapped modes, with and without SSAA at both game sizes. It
independently checks every presented texel against the resolved overscan image,
including across camera snap boundaries, and records scene raster differences
at those boundaries separately. It also checks fixed sample-buffer reuse,
deterministic return to a pose, rotation changing the image, and UI exclusions.
An independent planar fixture checks the expected sample centers, normals and
colors, front/behind world depth and back-face rejection after a half-turn.
The sampled-world checks additionally cover eight orbit angles, no uncovered
pixels in the initial camera framing, lazy creation, storage size, buffer reuse,
deterministic mode switching and independence from the world triangle draw count.

## Rendering performance

Run `mise run bench:voxel-resolution` with installed Chrome. Set
`PLAYER_BROWSER_CHANNEL` to select another installed Playwright browser channel.
The build finishes before measurement begins. The report is retained at
`build/compact-3d/resolution/river/performance.json`, including renderer identity,
driver/browser details, source hashes and per-run statistics.

The benchmark uses the actual `RiverRenderer` in a separate headless browser,
with the viewer's competing animation/status loop disabled. It presents at
1920×1080, warms each configuration for 45 frames, then measures 120 frames in
each of three rounds. Case order reverses in the middle round. Cases cover both
game resolutions, panning/orbiting, direct/1080p rendering, smooth presentation
on/off, and the sampled-world comparison. There are 36 runs and 4,320 timed
frames, plus warmup and a separate completion diagnostic. Other desktop GPU
activity is uncontrolled.

CPU submission is measured independently from asynchronous, paired GPU timer
queries around scene drawing and resolve/presentation. A frame's GPU total is
the sum of its two query results; component percentiles must not be summed.
Disjoint/incomplete GPU query results are reported as unavailable. Browser rAF
intervals describe headless scheduling, not physical monitor presentation.
A separate 30-frame-per-run diagnostic forces a one-pixel readback after drawing,
including synchronization/driver/readback overhead. It is not a proposed runtime
operation; see the distinction between submission and blocking readback in
[WebGL best practices](https://developer.mozilla.org/en-US/docs/Web/API/WebGL_API/WebGL_best_practices).
Startup, shader compilation and sample-cloud construction are excluded.

Measured on 2026-10-20 against renderer revision `a2672a6`, using hardware WebGL
through ANGLE/D3D11 on an RTX 3090, i7-11700K, and Chrome 155.0.8059.41. These
are the highest per-run p95 values, combining pan/orbit runs where applicable:

| Mode (1080p SSAA and smooth presentation) | Game output | CPU submission p95 | GPU p95 | Forced-readback p95 |
| --- | --- | --- | --- | --- |
| Pixel-snapped 3D | 320×180 | 0.20 ms | 2.03 ms | 4.40 ms |
| Pixel-snapped 3D | 640×360 | 0.20 ms | 2.02 ms | 4.20 ms |
| Whole-scene surface samples | 320×180 | 0.20 ms | 3.62 ms | 4.10 ms |
| Whole-scene surface samples | 640×360 | 0.20 ms | 3.54 ms | 4.90 ms |

All 4,320 GPU frame measurements were complete and nondisjoint. The preferred
pixel-snapped/SSAA/smooth configurations cover 1,440 frames: worst observed GPU
time was 2.19 ms, highest per-run rAF interval p95 was 8.20 ms, and no interval
exceeded 18 ms. Their scene-draw p95 reached about 1.91 ms, while combined
resolve/presentation p95 reached 0.19 ms. Run-to-run GPU times varied, so these
results use conservative per-run p95 values rather than the fastest run.

This supports a 16.67 ms rendering budget for this scene on this desktop. It
does not establish a minimum device or a complete game's 60 fps performance.
Both game outputs render roughly 2.1 million internal pixels, including overscan;
choosing 320×180 does not make the 1080p render four times cheaper. The current
scene submits about 1.03 million triangle vertices with resident static geometry
and baked lighting. Cartridge execution, gameplay, dynamic lighting/shadows,
asset streaming, larger scenes and the standalone native player are unmeasured.

Keep snapped 3D plus SSAA and smooth presentation as the visual baseline. The
next gate is a console GPU backend on native and browser running the same
cartridge workload, followed by integrated/mobile GPU measurements. Preserve
the CPU renderer as a reference. If those measurements need more headroom,
test chunk visibility, compatible face merging and lower internal-resolution
quality tiers before changing the preferred visual style. These results do not
qualify the current console software rasterizer for this workload.

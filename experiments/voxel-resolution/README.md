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
cobbled path, adventurer and arched red bridge over a stream. The scene fills
the viewport, with no scoreboard or exposed platform boundary. Terrain is
evaluated procedurally at world X/Z coordinates beyond the camera; a bounded
cache stores only the placed props, not the world terrain. The camera sees a
window into that terrain rather than an isolated volume. Every output pixel
must intersect scene geometry or terrain; generation asserts this independently
at each resolution. This does not implement chunk streaming in the console.

Its page is generated at `build/compact-3d/resolution/river/index.html`, or
`http://127.0.0.1:8081/resolution/river/index.html` on the existing demo server.

## Regenerate and view

From the repository root:

```sh
mise run build:voxel-resolution
mise run serve:voxel-resolution
```

Open the printed player URL, or `http://127.0.0.1:8080/index.html` with the
default port. Set `PORT` to select another port. When the existing 3D demo server
is running on port 8081, the same generated page remains available at
`http://127.0.0.1:8081/resolution/index.html`.

The source files in this directory are the canonical scene and comparison page.
The task regenerates PNGs, the page and a diagnostic report under the ignored
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

This is a standalone CPU voxel raycaster for evaluating visual style. It does
not run through either cartridge SDK or the console renderer. Its shadows and
local face occlusion are not evidence of implemented console API support, and
1080p is not a new console display mode. Timings in `report.json` include image
generation and are not console benchmarks. Static images do not evaluate motion
shimmer.

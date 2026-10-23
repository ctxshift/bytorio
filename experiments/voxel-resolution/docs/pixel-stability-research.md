# Stable pixels during 3D motion

Research date: 2026-10-19. This note separates public developer statements about
Shadowglass from ideas to evaluate in the riverside experiment. No renderer or
SDK behavior changes are implemented as part of this research.

## What the developer confirms

The official site describes real-time rendering with full 360-degree movement,
including walking around and examining objects from different angles. It does
not publish the rendering algorithm. [Official project site](https://shadowglassgame.com/)

In a direct developer interview published on 2026-05-19, the developer explains:

- The scene uses conventional 3D rather than voxels; manually authored 2D pixel
  work is optional.
- Custom shaders and rendering code work together. Point filtering and lookup
  tables are only surface components of more extensive pixel stabilization.
- The implementation uses Godot, including modifications to its renderer.
- A complete technical breakdown is deferred because the pipeline is changing.
- Readability requires asset variations at different distances. Palette,
  shadows, lighting and stepped animation require deliberate artistic choices.

These are the developer's own explanations, rather than the interviewer's
interpretation. [Developer interview](https://80.lv/articles/interview-how-project-shadowglass-creates-its-impossible-fully-3d-pixel-art-look)

## What remains unknown

The reviewed primary sources do not establish whether the stabilization uses
cubemaps, reprojection, persistent shading caches, world-space sampling,
object-space grids, camera snapping or pre-rendered object images. They also do
not specify the internal render resolution, sample count or performance cost.
Calling any one of those techniques the confirmed Shadowglass algorithm would
go beyond the evidence. The interview explicitly defers the detailed breakdown.
[Developer interview](https://80.lv/articles/interview-how-project-shadowglass-creates-its-impossible-fully-3d-pixel-art-look)

## Relevance to this experiment

Local code inspection: `RESOLVE_FRAGMENT` in
[`river-live.js`](../river-live.js) averages current-frame
samples in fixed output-pixel blocks. Rabbit translation and camera target remain
continuous. There is no history-buffer accumulation or temporal anti-aliasing.
Consequently, an edge crossing the output grid changes its coverage and filtered
color between frames. This is an expected mechanism for pixel swimming, rather
than evidence of a temporal ghosting bug. A controlled capture would still be
needed to attribute the user's entire observed effect to it. Fractional display
enlargement can add separate uneven-pixel artifacts.

The following are engineering hypotheses for our orthographic voxel scene,
not claims about Shadowglass:

- Supersampling can smooth a silhouette while its filtered edge colors still
  change as geometry crosses output pixels. Reducing jaggedness and preserving
  a stable pixel pattern during motion are different goals.
- A fixed-angle rabbit can be rendered to a small image with a consistent local
  sampling origin, then positioned at integer output coordinates. This tests the
  requested baked-sprite appearance directly. Rotation or animation still needs
  updated images, and integration needs depth/occlusion handling.
- For camera translation at a fixed orthographic angle and scale, align the
  rendering camera to the output pixel grid. Test this independently from rabbit
  movement so that camera-induced changes are distinguishable from animation.
  With the current 180-unit view width, output pixels span 0.5625 world units at
  320 pixels wide or 0.28125 at 640. Snap projected camera/object translation,
  keeping simulation positions continuous; rounding world X/Z independently is
  not equivalent to aligning this angled view's image grid.
- Rotation, zoom and perspective change the projection itself. A translated
  cached image cannot reproduce all resulting visibility changes; those cases
  require a broader stabilization strategy or an accepted visual compromise.

Compare direct rendering, current supersampling, pixel-aligned orthographic
movement and a cached rabbit image on identical motion paths at both output
resolutions. Inspect silhouettes, shade changes and occlusion frame by frame.
Treat the experiment as a choice about visual behavior, not proof that an
unpublished external rendering technique has been reproduced.

## Related public technique, separate from Shadowglass

The experimental preprint
[Texel Splatting: Perspective-Stable 3D Pixel Art](https://arxiv.org/abs/2603.14587)
describes sampling scene geometry from a world-anchored cubemap and projecting
its texels as quads. It explains why a single camera snap can stabilize fixed
orthographic translation but cannot correct every depth under perspective.
Its disclosed limitation is newly visible geometry at probe boundaries.
This is a primary description of an independent technique, not confirmation of
Shadowglass internals or a measured recommendation for this console. No source
code from the paper or related implementations was copied.

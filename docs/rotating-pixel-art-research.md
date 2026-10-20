# Stable pixel art under free rotation

Research date: 2026-10-19. This extends [the initial stability note](pixel-stability-research.md).
The proposed experiments below are original engineering hypotheses, not a
reconstruction of an unpublished renderer. No implementation was copied or
performance measured for this note.

## Evidence and conclusion

Shadowglass's developer confirms conventional 3D geometry, several cooperating
shaders/rendering techniques, deeper pixel stabilization beyond point filtering
and lookup tables, and modifications to Godot's renderer. The detailed method
remains undisclosed. The developer also describes distance-dependent assets and
deliberate lighting, palette and animation choices.
[Direct developer interview, 2026-05-19](https://80.lv/articles/interview-how-project-shadowglass-creates-its-impossible-fully-3d-pixel-art-look)

The official site promises real-time rendering and unrestricted viewing around
objects; it does not specify the stabilization mechanism.
[Official project site](https://shadowglassgame.com/)

**Working hypothesis:** retain the identity and appearance of discrete surface
samples across views, then solve their visibility and output placement separately.
This is a stronger starting point for rotation than snapping one camera position.
It is consistent with the public evidence, but that evidence cannot distinguish
surface grids, probes, reprojection or a different custom method.

There are three separate goals:

- **Surface stability:** a mark remains attached to the same part of an object.
- **Shading stability:** the mark keeps its color while lighting and pose are fixed.
- **Raster stability:** its displayed pixel cluster changes only in deliberate steps.

The first two do not guarantee the third. Under rotation, projected areas and
silhouettes change. A pixel can split, disappear or reveal another surface. An
exactly unchanged sprite pattern cannot also show geometrically accurate arbitrary
rotation. The practical target is coherent, discrete changes rather than zero
change. Pure camera look rotation, orbiting an object, and rotating the object
itself must be tested separately.

## Ranked architectures to test

This ranking reflects fit to the desired behavior and experiment cost, not a
probability that Shadowglass uses a particular implementation.

| Rank | Hypothesis | What it can preserve | Main failure to expose |
| --- | --- | --- | --- |
| 1 | Persistent object/surface cells, stable shading, separate visibility | Marks and diffuse colors through camera and rigid-object motion | Final coverage still changes; thin features and grazing angles create holes or crowded samples |
| 2 | World-anchored depth/normal/color probes, reprojected or splatted | Static environment detail during look rotation and nearby movement | Newly visible geometry, probe transitions, moving objects and sample density changes |
| 3 | Object-local rasterization with fixed pivot, angular views and depth | Strong baked-sprite appearance for a small actor | View-switch popping, wrong parallax, missing hidden surfaces and intersection errors |
| 4 | Depth/normal/ID-validated temporal reuse | Existing visible regions and shade persistence | Ghosting, stale lighting, rejection flicker and no data for unseen surfaces |
| 5 | Camera, vertex or final-projection snapping alone | Quantized screen motion in restricted cases | Rotation still changes coverage; independent vertex rounding can deform silhouettes |

Texture-space shading already separates appearance evaluation from screen
visibility and supports reuse of stored texel shading across frames. This is
evidence that the first architecture is technically established, not evidence
that it produces pixel art automatically.
[NVIDIA texture-space shading description](https://developer.nvidia.com/blog/?p=11950)

Surface elements can carry position, normal and color and be projected with
visibility and hole handling. That supplies a representation for experiment 1;
its reconstruction and filtering choices would need to be designed for this
art style.
[Surfels: Surface Elements as Rendering Primitives](https://www.merl.com/publications/TR2000-10)

The independent *Texel Splatting* preprint captures geometry into fixed-origin
cubemaps and displays their samples as quads. It documents an eye-probe fallback
for missing geometry and transitions between snapped probe origins. Its stated
open issues include animated geometry, specular materials and LOD. These are
material limits, not a complete production solution.
[Preprint, method and limitations](https://arxiv.org/html/2603.14587v1)

Interpret “rotation invariance” narrowly: a fixed cubemap's sample indexing does
not change when the viewing camera turns at the same position. Its projected
screen coverage can still change. Moving around an object changes visibility;
rotating the object changes what the probe captures. A world-space quad also
does not generally project to a constant, axis-aligned screen square. These are
geometric consequences, not additional claims made by the developer.

Depth sprites improve on flat billboards. Multiple depth layers can retain
surfaces hidden behind the first visible layer, at additional storage cost.
[Layered Depth Images](https://www.microsoft.com/en-us/research/publication/layered-depth-images/)
For our experiment, a single captured color/depth image should therefore be
treated as valid over a bounded view range, not a complete rotating object.

## Proposed construction

Start with a closed, rigid object and a small set of surface samples. A sample
stores a stable object/face/cell identity, local position, local normal, material
and palette result. Use a face-local grid for the initial box-like geometry;
keep those cells fixed as the camera moves. For smooth meshes, a fixed UV or
barycentric parameterization is a later extension. Nearest sampling of a UV
texture alone is a useful control but leaves silhouette coverage unresolved.

Transform samples with the object, project them, and compare two display rules:
surface-aligned splats versus screen-aligned squares snapped to logical pixels.
The former preserves the surface footprint better; the latter enforces the
desired square-pixel appearance but can distort coverage. Resolve depth and
near-equal-depth ties deterministically. Expose holes in a diagnostic color
before adding dilation, since filling holes can erase gaps and thin silhouettes.

Shade at the persistent sample, initially with fixed diffuse lighting and no
history buffer. This isolates sampling from temporal smoothing. Later, cache
lighting only while its material, transform, lights and shadow dependencies are
valid. Keep view-dependent highlights separate. Surface samples can follow
deformation through a stable parameterization; their world normals and lighting
still need updating. Freezing a previous frame's color is not sufficient.

For a small actor, covering all faces avoids the hidden-surface deficit of a
single probe. For a large static scene, a bounded probe cache may be cheaper than
maintaining every surface sample. That cost comparison remains unmeasured.

Introduce nested sample-density levels only after one density works. Parent/child
cell identities and separate entry/exit thresholds can make LOD changes
repeatable. Palette bands can use similar hysteresis. Both add history and must
be checked for lag and different forward/reverse results. Screen-space animated
dither would undermine the very stability being measured.

## Falsifiable experiment sequence

Use identical scripted poses at 320 and 640 logical pixels wide, with integer
display enlargement. Record logical-resolution frames and diagnostic IDs;
screenshots of an interpolated browser canvas are insufficient.

1. **Translation control.** Keep camera angle, object pose, scale and light fixed.
   Compare direct rendering, supersampling, snapped projection and the separate
   actor image. After compensating integer placement, the actor image should be
   bit-identical. Failure reveals sampling-origin, crop, filtering or compositing
   changes before rotation is involved.
2. **Surface identity test.** Rotate a textured box through a full turn, then orbit
   the camera independently. Compare ordinary nearest-textured triangles with
   persistent surface samples. Track sample IDs and colors only where the same
   surface remains visible. Reject a method that merely blurs detail or leaves
   screen-attached marks. Repeat with a thin ear-like shape and an occluding post.
3. **Coverage test.** Toggle surface-aligned splats and snapped screen squares.
   Count uncovered reference pixels, false foreground coverage, silhouette
   changes and ID turnover separately from color changes. A stable interior with
   unstable silhouette means shading is solved but coverage is not.
4. **Bounded sprite test.** Capture fixed-pivot views at several angular spacings,
   using consistent pixel density and bounds. Compare nearest view selection
   with depth reprojection inside a view interval. Move the actor behind and in
   front of the post. Reject flat-depth compositing if limbs receive incorrect
   occlusion; measure view-switch jumps rather than hiding them with blending.
5. **Probe test, only if needed.** Capture one fixed probe in a scene with near
   and far objects. First turn the camera in place; then translate past an
   occluder and cross a probe boundary. Display missing regions explicitly.
   Add current-view fallback separately and measure whether shimmer is simply
   transferred into those regions.

Also reverse each motion and return to the exact starting pose. With fixed
lighting and no intentional history, the returned frame should match. Do not
score total frame difference as instability: correct movement and disocclusion
necessarily change pixels. Compare common-visible surfaces using IDs, and report
the excluded/disoccluded fraction so a method cannot win by discarding hard areas.

## Console and WebGL feasibility

The existing native/browser player shares Odin, and its mesh path already has
transforms, depth resources and a work budget. See
[development](development.md) and [mesh implementation](../runtime/odin/resources/mesh.odin).
A bounded CPU reference can transform samples and stamp into a logical color,
depth and ID buffer. This tests the algorithm without requiring a new GPU API.
Reserve explicit sample counts, memory, covered-pixel work and cache lifetimes;
route eventual resource changes through the existing protocol and both SDKs.

The standalone WebGL experiment can use sample buffers and repeated quad draws
or instancing, offscreen color/depth targets and nearest final enlargement. Begin
with precomputed static samples and simple fragment lighting; compute shaders
are not necessary for this proof. Keep a current-view mesh rendering as the
visibility reference. GPU/browser capability checks and timings are still needed.

The current [riverside comparison](../experiments/voxel-resolution/README.md)
now includes snapped 3D and a separate color/depth rabbit sprite as translation
controls. Its orbit option deliberately exposes their limits; it does not
implement the persistent-surface or probe experiments described here.

Choose the smallest successful result: a local actor image if translation is the
requirement, persistent surface samples if rotation requires them, and probes
only if the environment experiment justifies their additional visibility and
cache machinery. Current research does not establish Shadowglass's exact method
or demonstrate acceptable console performance. This note changes documentation
only; runtime validation and visual acceptance remain future experiment work.

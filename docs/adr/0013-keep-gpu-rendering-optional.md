# Keep GPU rendering optional

Use CPU rendering as the default and exact conformance reference, with optional
host-selected GPU execution through the same resource APIs, so games can run
without requiring a GPU backend.
Treat GPU resources as derived representations of runtime-owned data rather than
independent cartridge-visible ownership.
GPU execution and quality settings can improve throughput or presentation, but
do not promise identical pixels across drivers or a guaranteed frame rate.

Rendering contracts: [compact 3D](../compact-3d.md) and
[textured 3D](../textured-3d.md).

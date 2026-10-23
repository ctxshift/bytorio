# Import artist model formats during development

Convert the supported glTF and GLB subset into bounded normalized data and SDK
modules that create ordinary textures, materials and meshes.
This keeps general-purpose model parsing and its dependencies out of game
execution and avoids adding a separate runtime model interface.
Accept an explicit import subset and generated-source overhead for these static
assets rather than promising that every artist-format feature can run unchanged.

Import scope: [static model import](../model-import.md).

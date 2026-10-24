# Internal engineering reports

These documents record implementation evidence for console contributors. They
are not SDK instructions or performance promises for games. The website's
public guide list is maintained separately in [the site catalog](../../site/catalog.mjs).

## Shared measurements

The [standalone CLI distribution plan](cli-distribution.md) tracks authoring-tool
packaging and dependency management work separately from measurement evidence.

- [Graphics upload and rendering](measurements/graphics-measurements.md)
- [PCM audio delivery](measurements/audio-measurements.md)
- [Synthesis and effects](measurements/synthesis-measurements.md)
- [Compact 3D](measurements/compact-3d-measurements.md) and its [reference data](measurements/compact-3d-reference.json)
- [Build iteration](measurements/build-iteration-measurements.md)

Reports specific to an example or experiment belong in that project's `docs/`
directory, along with their checked-in data. For example, the
[kart quality report](../../examples/kart3d/docs/kart-quality-measurements.md)
and [JSON summary](../../examples/kart3d/docs/kart-quality-measurements.json)
live together.

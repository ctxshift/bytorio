---
name: bytorio-cartridge-art
description: Create or revise Bytorio game sticker artwork, compose the standard cartridge cover with byt cover, and package the approved art into a playable PNG cartridge.
---

# Bytorio cartridge art

Create game-specific square label art, then let the Bytorio CLI supply the
standard cartridge shell and markings. A sticker is artwork; a blank cartridge
is the composed cover; a packed cartridge contains the playable game.

## Establish the brief

Read the game's manifest and existing art before generating anything. Use its
actual title, language and display resolution. Learn the visual theme from the
game, screenshots or the user's brief; preserve approved art direction when
editing. Ask only for information that materially changes the result and cannot
be inferred from the project.

Use the available image-generation tool for new illustrations or visual edits.
Inspect reference images before editing them. Follow that tool's image-input and
output-saving requirements. If generation is unavailable, explain the limitation
instead of substituting unrelated stock art.

## Design the sticker

- Generate only a flat square label, preferably around 1024 x 1024 pixels.
- Keep the title legible at thumbnail size with comfortable margins. Use the
  exact title; include a short tagline only when appropriate to the brief.
- Feature a few recognizable elements of the game, with a clear focal point.
  Avoid turning the label into a crowded gameplay screenshot.
- Do not generate the plastic cartridge, Bytorio logo, language or resolution
  markings. The compositor supplies those consistently.
- Choose opaque or transparent artwork deliberately: transparent pixels reveal
  the cartridge shell, not white paper.

Style is game-specific. For a simple lo-fi brief, favor flat paper-like shapes,
muted colors, restrained print grain, open space and minimal small details.
Willow Junction's approved direction was a cozy station, a steam locomotive with
two passenger cars, a willow tree, sage and dusty coral tones, and a readable
title. Treat this as an example, not a required theme for future games.

Adapt this prompt structure:

> Square flat sticker artwork for [game title]. [Main subject and composition].
> [Chosen palette, medium and detail level]. Exact title: "[game title]".
> [Optional tagline]. Clear typography and safe margins, readable at thumbnail
> size. Label only; no cartridge shell, platform branding or technical markings.

Inspect generated art for spelling, composition and requested visual details.
When revising, preserve the previous useful version and replace the canonical
asset only after selecting the new result. Save the final prompt and enough
generation provenance to repeat the direction using project-relative paths.

## Compose and pack

Work from the game project root. Prefer existing project tasks; otherwise use
the commands below. Check the installed CLI's `byt cover --help` and
`byt pack --help` if its behavior differs. Record or retain the project's CLI
pin for reproducible composition; do not silently upgrade tools to make art.

The sticker input must be a square, static, noninterlaced, 8-bit RGB or RGBA PNG,
1 through 4096 pixels on each side and at most 32 MiB. Export unsupported image
encodings as RGB/RGBA before composition. Never use a packed cartridge as a
sticker or blank cover.

Suggested portable paths are `art/sticker.png` and `art/cover.png`; preserve an
existing project's naming convention. For a Luau game at 640 x 360:

```sh
byt cover art/sticker.png --output art/cover.png --language luau --display 640x360
```

Substitute the manifest's actual language and display. These flags label the
cover; they do not change the game configuration. Use `--force` when intentionally
replacing the previous generated blank cover. Keep the source sticker separate.

The CLI owns the shell, wordmark, label placement and recessed lettering. Layout
v1 produces an 839 x 1024 transparent cover with a 554 x 554 sticker aligned to
the inner rails. Do not manually recreate or overlay these components. The full
square is resized without cropping, so check small text after composition.

For recurring builds, set the manifest's top-level cover field:

```toml
cover = "art/cover.png"
```

Then run the project's packaging task or `byt pack .`. For a one-off output:

```sh
byt pack . --cover art/cover.png --output dist/my-game.png
```

Only package when a game project exists and packaging is part of the request.
An artwork-only request can end with the sticker or blank cover. Neither command
publishes anything; distribution is a separate action.

## Verify and deliver

Inspect the composed cover, including the title at reduced size, sticker edges,
transparency and correct language/display markings. Confirm that packaging
succeeded and open the packed output in a compatible player or run the project's
cartridge check when delivering a playable cartridge. Report checks actually run.
An art-only change does not by itself call for unrelated runtime test suites.

Show the result and identify the saved sticker, blank cover, prompt record and,
when produced, playable cartridge. Send the original packed PNG as a file:
resizing, re-encoding or image-sharing services can strip its embedded game data.

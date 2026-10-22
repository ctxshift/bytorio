# Console website

The site lives in `site/` alongside the console source. It is a static landing
page, searchable documentation library, and playable demo showcase. The Bytorio brand uses a charcoal palette, red accents, voxel illustrations, and
a fox mascot.

## Build and preview

With the development toolchain installed, run from the repository root:

```text
mise exec -- npm ci
mise run build:site
mise run serve:site
```

Open `http://127.0.0.1:8088/`. `build:site` sequentially builds the RPG and racing
exports, then produces `build/site/`. `build:site:pages` regenerates only the site
from existing exports for faster content and styling iterations. It fails if
either demo cartridge is absent. It does not verify that staged exports are fresh;
use the complete build for releases. Deploy the contents of `build/site/` to an
HTTPS static host with `.wasm` served as `application/wasm`. No application server,
account, CDN runtime, or database is required. Relative URLs support subdirectory
hosting. Typography uses Google Fonts with local system fallbacks.

`HOST` and `PORT` configure the local preview server. To try a phone on the same
network, bind `HOST` to `0.0.0.0` and open the machine’s LAN address. AudioWorklet
requires a secure context: use an HTTPS preview for full audio testing on a phone.
The server is for development, not production hosting.

## Content and documentation

`site/catalog.mjs` lists games and the primary documentation navigation.
`site/templates.mjs` owns the site layout and editorial content. The build renders
tracked Markdown, including the SDK reference and specifications, into HTML. It
preserves headings, tables, fenced code, and links to available documents and
source files. References to ignored local build artifacts are labeled rather than
published as broken links. Source files linked from guides receive readable code
pages. Search is local, loads its index on demand, and searches full document text.

`site/site.css` owns the responsive dark brand theme: pixel headings, red buttons,
illustrated handheld and cartridge frames, and the fox logo. Body copy and
reference material use readable text fonts. Documentation has a desktop table
of contents, while the showcase filters the real games by category. Brand artwork
lives in `site/assets/brand/`; the decorative handheld shows a real game capture. `site/player.css` styles the
embedded player and large mobile controls to match.

Game images in `site/assets/` are captures of the real cartridges. When gameplay
art changes, refresh them with `mise run capture:site` after building the site,
then rebuild the pages. The capture task requires the project's Playwright browser.

## Playing and touch input

The showcase ships the same Wasm runtimes and PNG cartridges as the console
exports, with licenses retained. Game pages load the player only after a visitor
chooses **Load game**. **Start game** unlocks audio. Both Luau and Odin variants are
available; switching language or restarting starts a new session. Download links
provide the original PNG cartridge without image transformations.

The website adds presentation CSS and touch controls to a copy of the canonical
player markup, without editing the runtime. Pointer capture supports simultaneous
direction and action touches. Pointer cancellation, lost capture, blur, and page
visibility changes release held controls. The controls remain inside the fullscreen
container. Keyboard users can navigate away with Tab; arrow keys are consumed only
while the game canvas has focus. The console's existing gamepad input is retained.

Copper Circuit and Mossglen use the CPU renderer, require no WebGPU, and are
intended for desktop and mobile browsers with WebAssembly. Performance depends
on the device. GPU-specific demos should be added only with their actual backend
capability check and a clear unsupported-browser fallback; they are not part of
the current showcase. Physical iOS/Android hardware, speakers, and controllers
still need live testing before claiming device certification.

## Validation

```text
mise run validate test:site
mise run validate
```

The site check builds pages from staged exports, checks local links, searches the
documentation, verifies responsive layout, starts both languages of both games,
and exercises touch input and cancellation in mobile browser emulation. Reports
and screenshots remain under ignored `build/site-verification/`. Full project
validation retains the existing console conformance gates and includes the site
check. Building the console exports is required before a standalone focused run.

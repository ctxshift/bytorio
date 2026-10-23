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

## Fly.io hosting

Production uses the `bytorio` app in the `context-shift` Fly.io organization,
with `bytor.io` as its custom domain. The container serves only the generated
`build/site/` output using nginx, including the documentation and game exports.
The Docker build context excludes other checkout files. HTTPS is enforced by
Fly Proxy, and nginx serves WASM with `application/wasm`. Files revalidate on
subsequent requests so updated game scripts and binaries stay consistent.

After signing in with `fly auth login`, create the app once if it does not exist:

```text
fly apps create bytorio --org context-shift
```

Run releases from the repository root:

```text
mise run deploy:site
```

The task builds the current demo exports and site, runs the site checks, and
deploys with `fly.site.toml`. The initial setup uses one shared CPU with
256 MiB memory in Chicago; one machine stays running to avoid cold starts.
Provision the custom-domain certificate with `fly certs add bytor.io -a bytorio`
and use the DNS records reported by Fly. Verify the certificate with
`fly certs check bytor.io -a bytorio` after updating DNS.

## Content and documentation

`site/catalog.mjs` lists games, the primary documentation navigation, and the
explicit `publicDocuments` list. Add game-author guides and SDK/tool references
there to publish them. Other tracked Markdown is not automatically published:
ADRs, planning notes, research and benchmark reports stay in the source checkout.
Shared measurement reports and their data live in `docs/internal/measurements/`;
example and experiment reports belong beside their owning project.

`site/templates.mjs` owns the site layout and editorial content. The build renders
only the public Markdown selection into HTML. It
preserves headings, tables, fenced code, and links to available documents and
source files. References to unpublished documents and ignored local build artifacts are labeled rather than
published as broken links. Source files linked from guides receive readable code
pages. Search is local, loads its index on demand, and searches only public document
text. Each build clears the generated documentation and source-page directories
so removed pages cannot remain available from an earlier build.

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

# Bytorio

The shared vocabulary for making, running and distributing Bytorio games.
These terms describe the console and its authoring model; feature contracts,
supported limits and architectural decisions belong in the area documentation.

## Language

### Console and execution

**Bytorio**:
A software game console with its own game-making capabilities and portable
cartridges, rather than an emulation of an existing hardware console.

**Player**:
The application that loads a cartridge and presents its game to the person
playing, on a native or browser host.
_Avoid_: Emulator

**Native player**:
A standalone player for a supported operating system, usable without the
game-development toolchain.

**Browser player**:
A player that runs cartridges within a web browser.

**Runtime**:
The shared console machinery that supplies a running cartridge with game timing,
input, graphics, audio and resource services.

**Host**:
The environment in which a player runs and obtains platform services, such as
a browser or a native operating-system environment.

**Cartridge guest**:
The game program running within the console's permitted services and boundaries,
separate from the host and its resources.

**Cartridge session**:
One loaded instance of a cartridge, with its own running game state and resource
lifetimes, ending when the cartridge is unloaded or the session fails.

**Game lifecycle**:
The cartridge's initialization, simulation-update and drawing phases.

### Authoring and distribution

**Cartridge**:
A shareable game containing its program and assets, loaded by a compatible player.
_Avoid_: ROM

**PNG cartridge**:
A cartridge packaged as a viewable image containing both cover art and the
complete game payload.
_Avoid_: Screenshot, cover image (when referring to the complete cartridge)

**Cover art**:
The visible image of a PNG cartridge, distinct from the game program and assets
packaged with it.

**Cartridge shell**:
The standard reusable image of the cartridge casing, shared by the website and
the CLI's cover compositor.

**Sticker**:
Square game artwork placed within the shell's fixed label region. The sticker
does not include the shell or the generated platform, language and display markings.

**Blank cartridge**:
Artwork consisting of the shell, fitted sticker and molded markings, without a game
payload. Created by `byt cover`; it is a cover image, not yet playable.
_Avoid_: Empty game, unloaded cartridge

**Packed cartridge**:
A playable PNG cartridge containing cover art and the complete game payload,
created by `byt pack` or a player build. Packing preserves the cover's pixels.
_Avoid_: Burned cartridge, loaded cartridge (when describing packaging)

**Packing**:
Embedding the built game payload into a PNG cover. This is a local preparation
step; it does not upload or publish the game to a service.

**Publishing**:
Making a packed cartridge available to players, for example by sharing the PNG
or hosting a player export. A packed cartridge need not have been published.

**Cartridge payload**:
The game program and packaged data carried by a cartridge, distinct from its
visible cover art and the player that runs it.

**Player export**:
The standalone player and its required dependencies and notices, prepared for a
native or browser host. A cartridge and its launcher customization are separate
from the player export.

**Game project**:
The authoring sources, assets and project settings used to build a cartridge.

**Project manifest**:
The declaration of a game project's identity, entry point, language, assets and
requested console capabilities.

**Authoring SDK**:
The game-facing language interface to Bytorio's console services. The Luau and
Odin SDKs express the same console capabilities in their respective languages.

**byt CLI**:
The command-line authoring tool for creating, checking, building, packaging and
running Bytorio game projects.

**Example project**:
A runnable game or scene demonstrating supported console capabilities and their
use from the authoring SDKs.

**Experiment**:
An exploratory project for evaluating a possible capability or rendering approach;
its presence does not make that behavior part of a supported console profile.

### Compatibility and capabilities

**Capability profile**:
A named contract defining the console features and portable limits a cartridge
requires from a player.
_Avoid_: Hardware tier, performance rating

**Published profile**:
A capability profile offered as an established compatibility contract for game
authors, distinct from an experimental preview.

**Preview profile**:
An explicitly selected experimental capability contract, separate from the
published profile's guarantees.

**Game ABI**:
The binary interface contract between a cartridge guest and the player.

**SDK version**:
The version of the authoring interface requested by a game project or declared
by a cartridge.

**Resource protocol**:
The contract for expressing resource and graphics/audio operations between a
cartridge and the runtime.

**Cartridge container version**:
The version of the packaging format that carries a cartridge's program and data,
independent of its game ABI and authoring SDK version.

**Profile negotiation**:
The compatibility check matching a cartridge's declared requirements to a
player's supported contracts before game initialization.

**Capabilities**:
The features and limits available to a cartridge under its validated profile,
rather than an estimate of the host's performance.

### Cartridge content and memory

**Indexed content**:
Immutable data packaged in a cartridge and addressed independently of the game
program's working memory.

**Content entry**:
One individually addressable byte sequence in a cartridge's indexed content.

**Content ID**:
The cartridge-local identifier of a content entry, distinct from a runtime
resource handle or a source asset's filename.

**Guest memory**:
The cartridge program's working memory, distinct from packaged content and
runtime-owned resources.

**Resource budget**:
The allowance for runtime-owned resources under a capability profile, distinct
from cartridge storage, guest memory and total host memory use.

### Resource ownership

**Typed resource**:
A runtime-owned graphics or audio object that a cartridge accesses through a
handle of the appropriate kind.

**Resource handle**:
A typed reference valid for one resource lifetime within one cartridge session.
Destroying the resource or ending the session invalidates it.
_Avoid_: Resource pointer

**Resource transaction**:
An ordered group of resource operations accepted together or rejected without
publishing partial changes.

**Resource dependency**:
A relationship in which one live resource retains another resource it needs,
preventing the retained resource from being destroyed first.

**Upload**:
A transfer of game-owned data into a runtime-owned resource, using a snapshot
of the supplied data.

**Pixel buffer**:
Game-owned, editable pixel data used to prepare image uploads or receive image
readbacks.

**PCM buffer**:
Game-owned audio values grouped into frames and channels, used to prepare sample
resources or supply audio streams.

### Display and 2D graphics

**Display mode**:
The console's selected logical game resolution, distinct from the host window
or browser viewport size.

**Logical display coordinates**:
Positions in the game's display space, shared by drawing, pointer input and
text-field placement.
_Avoid_: Window pixels (when referring to game coordinates)

**Texture**:
An image resource whose pixels can be uploaded and sampled during drawing,
distinct from a render target.

**Render target**:
An image resource that receives drawing commands in a graphics pass.

**Screen target**:
The reserved color render target whose dimensions follow the active display mode.

**Graphics pass**:
An ordered drawing scope with one color target and its drawing state.

**Graphics pipeline**:
An immutable resource defining how a graphics pass combines incoming pixels with
its target, including blending, write masks and stencil rules.

**Palette**:
A resource mapping indexed image or voxel values to colors.

**Composition table**:
A resource defining the output index for each pair of source and destination
indices during indexed drawing.

**Row table**:
A presentation resource assigning a palette and source offset to each display row.

**Stencil attachment**:
An auxiliary image attached to a color target that controls which fragments may
change that target.

**Presentation**:
The selection of a completed image as the next visible game display.

**Readback ticket**:
A request identifier for a copy of image pixels that the cartridge can retrieve
after the result becomes available.

### 3D graphics and model authoring

**Colored mesh**:
An immutable resource containing indexed triangle geometry with a color at each
vertex.

**Textured mesh**:
An immutable resource containing indexed triangle geometry with vertex tints and
texture coordinates, drawn with a material.

**Material**:
A resource combining a referenced texture with the sampling and surface rules
for textured 3D drawing.

**Cutout material**:
A material that discards texture fragments below an alpha threshold and treats
surviving fragments as opaque, including their depth writes.

**Effect material**:
A material for blended 3D effects with independently selected depth testing and
depth writing.

**Camera resource**:
An immutable description of a 3D view and projection together with its lighting
and fog settings.

**Depth attachment**:
A resource recording depth values used to determine which 3D fragments are
visible in a render pass.

**Voxel volume**:
A resource containing a three-dimensional grid of palette-indexed cells with
an explicit empty-cell value.

**CPU reference renderer**:
The software renderer defining Bytorio's baseline graphics behavior and reference
conformance results.

**GPU execution**:
An optional host rendering path using the same cartridge-facing resource
interfaces as CPU rendering.

**GPU-resident mesh**:
A reusable GPU representation of a runtime-owned mesh, rather than a separately
owned cartridge resource.

**Model import**:
Development-time conversion of an artist-authored model into Bytorio resources
and generated modules for both authoring SDKs.

**Imported model**:
A prepared collection of geometry, materials and named rigid parts preserving
the source model's selected hierarchy.

**Model instance**:
A drawable use of an imported model with its own placement and part transforms.

**Model transform**:
The placement, orientation and scale of geometry for one 3D draw.

### Simulation and input

**Simulation tick**:
One fixed step of game time in which gameplay updates and input edges are
observed. Drawing can occur more or less often than ticks.
_Avoid_: Frame, render tick

**Rendered frame**:
One visual result produced by drawing the current game state, without advancing
simulation time. It need not correspond to a distinct physical display refresh.
_Avoid_: Tick

**Frame pacing**:
The player policy determining when rendered frames are requested, independently
of simulation ticks.

**Input snapshot**:
The game controls and pointer state supplied for a simulation tick.

**Input edge**:
A control's transition to pressed or released, observed at a simulation tick.

**Text-input field**:
The game-declared editing area whose committed text and selection are supplied
by the host's text editor.

**Committed text**:
The completed text available to the game from a text-input field, excluding
unfinished input-method composition.

### Audio playback and synthesis

**Audio frame**:
One position on an audio timeline containing a value for each channel. Source
frames address source audio; logical audio frames address the mixer's timeline.
_Avoid_: Simulation tick, rendered frame

**Sample resource**:
A reusable resource containing PCM sound data for playback or synthesis,
called a sample in the audio API.
_Avoid_: Voice, audio stream

**Voice**:
An explicitly selected playback slot carrying a sample, stream or instrument
note and its playback controls.
_Avoid_: Sample, audio channel

**Audio stream**:
A time-addressed source of PCM audio that voices can read independently.
Attaching or stopping a voice does not restart the stream's timeline.

**Ogg stream**:
An audio stream supplied by progressively decoding Vorbis content packaged in
the cartridge, with optional source-frame looping.
_Avoid_: Network stream

**Audio bus**:
A mixing destination for voices and child buses, with shared gain and optional
effects.

**Master bus**:
The final audio bus through which all mixed sound reaches player output.

**Instrument**:
An immutable synthesis graph defining the sound of a note, with independent
evolving synthesis state for each playing voice.

**Synthesis node**:
A typed element of an instrument or effects graph representing a sound source,
signal transformation or control signal.

**Wavetable**:
A synthesis resource containing repeating waveforms used as oscillator sources.

**Live source**:
A sample or wavetable whose scheduled edits are shared by active and future
synthesis playback.

**Bus effects**:
A signal-processing graph applied to a bus's mixed sound, independently of
individual note lifetimes.

**Audio completion**:
A report that a voice ended naturally, was stopped or was cancelled.

**Scheduling lead**:
The allowance between submitting audio work and its logical playback position,
giving the player time to deliver it. It is not a measurement of speaker latency.

### Persistent game progress

**Save slot**:
The cartridge's persistent location for one complete game-owned record.
_Avoid_: Save directory

**Save snapshot**:
A complete record submitted to replace a save slot's contents, with its format
and compatibility rules owned by the game.
_Avoid_: Save delta

**Committed save**:
The latest save snapshot whose storage operation has succeeded and which is
available to reads. A pending write does not replace it.

**Save identity**:
An explicit cartridge declaration that compatible builds should share a save
slot, independently of their filenames, artwork or program bytes.
_Avoid_: Game title, filename (when identifying shared saves)

**Legacy save adoption**:
The first-time creation of a stable save slot from an eligible older cartridge's
existing save. It changes storage identity, not the game's record format.
_Avoid_: Save-format migration

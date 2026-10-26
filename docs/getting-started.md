# Getting started with Bytorio

Bytorio lets you make a small game in Luau or Odin and share it as a PNG
cartridge. Start with Luau if you are new to programming. Both languages use
the same console capabilities.

You can [play the browser demos](https://bytor.io/showcase/) without installing
development tools. Choose **Load game**, then **Start game** to enable sound.

## Installation status

The **standalone CLI preview** creates
Luau and Odin projects and downloads versioned SDK bundles without Node, Bun,
mise or a source checkout. **It cannot build, check, run or pack games yet.**
For a playable game, continue with the source setup below on Windows x64 or
macOS Apple Silicon. The [CLI preview releases](https://github.com/ctxshift/bytorio/releases)
are available for Windows, Apple Silicon and Intel. Intel Mac supports the
standalone scaffolding preview; the pinned Odin release has no Intel compiler
for source builds. Choose a manual download below or use the
[mise installation workflow](#install-with-mise). Linux authoring packages are
not available yet.

## Download the CLI preview

Open the [releases page](https://github.com/ctxshift/bytorio/releases) and choose
the newest **Bytorio CLI** release (`byt-v...`), including previews. SDK releases
(`sdk-v...`) contain bundles rather than executables. Under **Assets**, download
the executable and matching checksum manifest listed below. The source-code
archives are not the CLI. No Node, Bun or mise installation is needed for a
manual download.

### macOS (Apple Silicon or Intel)

Choose your Mac's download below. In **Apple menu > About This Mac**, an Apple
M-series **Chip** means Apple Silicon; an Intel **Processor** means Intel.
See [Apple's chip identification guide](https://support.apple.com/en-us/116943).

| Mac | Executable | SHA-256 manifest |
| --- | --- | --- |
| Apple Silicon | `byt-macos-arm64` | `release-macos-arm64.json` |
| Intel | `byt-macos-x64` | `release-macos-x64.json` |

Download the executable and its matching manifest to **Downloads**, then open
**Terminal**. These commands use Apple Silicon; on Intel, replace
`byt-macos-arm64` with `byt-macos-x64`:

```sh
cd "$HOME/Downloads"
shasum -a 256 byt-macos-arm64
```

Compare the hash with the `sha256` value in the downloaded JSON manifest.
After it matches, rename the executable to `byt`, make it executable, and try it:

```sh
mv byt-macos-arm64 byt
chmod +x byt
./byt --version
./byt --help
./byt new preview-game
```

`--version` should match the selected release's version. The last command creates a Luau
project using the embedded SDK, with no additional download. Add
`--language odin` to create an Odin project in a different, nonexistent folder.
Intel Macs can create projects with this preview; the complete source workflow
below requires Apple Silicon on macOS.

Mac previews are ad hoc signed and **not notarized**. If macOS blocks the first
launch because the developer cannot be verified, follow
[Apple's instructions for opening a trusted download](https://support.apple.com/en-us/102445):
after the launch attempt, open **System Settings > Privacy & Security** and
choose **Open Anyway** for this executable, then rerun `./byt --version`.

To use `byt` from any folder, install it in your user bin directory:

```sh
mkdir -p "$HOME/.local/bin"
install -m 755 ./byt "$HOME/.local/bin/byt"
export PATH="$HOME/.local/bin:$PATH"
byt --version
```

The `export` applies to the current terminal. For macOS's default zsh, add that
same `export PATH="$HOME/.local/bin:$PATH"` line once to `~/.zshrc` and open a
new Terminal window to keep the command available. If you use another shell,
add it to that shell's startup file. No administrator access is needed.

### Windows x64

1. Choose a **Bytorio CLI** release from the [releases page](https://github.com/ctxshift/bytorio/releases).
2. Under **Assets**, download `byt.exe` and `release.json` into a folder you keep,
   such as a `bytorio-tools` folder.
3. Open PowerShell in that folder. Optionally verify the download by running
   `Get-FileHash .\byt.exe -Algorithm SHA256` and comparing it with `sha256` in
   `release.json`.
4. Run:

```text
.\byt.exe --version
.\byt.exe --help
.\byt.exe new preview-game
```

The version should match the selected release. The last command creates a Luau project
using the embedded SDK. Add `--language odin` to create an Odin project instead.
The Windows preview executable is currently unsigned.

PowerShell uses `.\byt.exe` to run a program in the current folder. You can
optionally add the folder containing the executable to your user PATH, reopen
the terminal, and use `byt` from any folder.

## Install with mise

On Windows x64, Apple Silicon or Intel Mac, install
[mise](https://mise.jdx.dev/getting-started). No Node, Bun or compiler is needed
to install or use the standalone preview.

### Pin a release (recommended)

Choose a **Bytorio CLI** release from the
[releases page](https://github.com/ctxshift/bytorio/releases). Add this one line
under `[tools]` in your own `mise.toml`, replacing `<version>` with the version
from that release and keeping the full `byt-v` tag prefix:

```toml
[tools]
"github:ctxshift/bytorio" = "byt-v<version>"
```

Then run from that folder:

```sh
mise trust
mise install github:ctxshift/bytorio
mise exec -- byt --version
mise exec -- byt new preview-game
```

Mise selects the correct Windows
or Mac asset, handles the raw executable, and exposes the command as `byt`.
The exact tag selects the preview directly, so no extra tool options are needed.
You can also install and write this pin with
`mise use github:ctxshift/bytorio@byt-v<version>`.

Add `--global` to `mise use` if you want a personal default. With mise shell
activation configured, use `byt` directly; `mise exec -- byt ...` also works
without activation. Run these consumer commands outside the Bytorio source
checkout, whose mise configuration manages the contributor toolchain.

To update, choose a new CLI release and change the full tag in `mise.toml`, or
run `mise use github:ctxshift/bytorio@byt-v<version>` again with the new version.
For checksum locks, automatic `latest` selection and an optional SDK task, see
[Advanced mise installation](mise-installation.md).

Choose a CLI release containing platform archives: `byt-windows-x86_64.tar.gz`,
`byt-macos-aarch64.tar.gz` or `byt-macos-x86_64.tar.gz`. Mise selects the matching
archive, which contains `byt.exe` or `byt` at its root. These names support the
short entry on older mise releases too. Releases predating the archives retain
their manual raw-binary downloads. Contributor-toolchain requirements are separate.

## Use a versioned SDK bundle

CLI release versions and SDK bundle versions are independent. On either
platform, choose an **SDK bundle** release (`sdk-v...`) from the
[releases page](https://github.com/ctxshift/bytorio/releases). Replace
`<sdk-version>` below with its version without the `sdk-v` prefix. Download it
once and reuse it offline:

```text
byt sdk install <sdk-version>
byt new pinned-game --sdk <sdk-version> --offline
```

These examples assume `byt` is on PATH. Otherwise, use `./byt` on Mac or
`.\byt.exe` on Windows from the folder containing the executable. Keep the
generated `byt.lock.json` with the game source; it pins the downloaded bundle.

With mise, use `mise exec -- byt sdk install <sdk-version>` and
`mise exec -- byt new pinned-game --sdk <sdk-version> --offline`.
An optional `sdk:install` task is shown in [Advanced mise installation](mise-installation.md).
SDK bundles are data managed by `byt`, so they do not need another mise backend
or a second `[tools]` entry. Use the embedded SDK by omitting `--sdk` when you
do not need a separately pinned bundle.

## Build and run your preview project

Trying `check`, `build`, `run`, `watch`, `pack` or `import` in this preview gives
an explicit unsupported-command message. These commands require the source CLI
below. To use the project you just created, run `mise run byt -- check <project>`
and `mise run byt -- run <project> --web` from that checkout, replacing `<project>`
with its path. Do not run `new` over an existing project. The source CLI does not
yet enforce the preview's SDK bundle lock; use the source revision identified
in the release notes when trying this fallback.

## Install the development tools

Install [Git](https://git-scm.com/downloads),
[mise](https://mise.jdx.dev/getting-started), and the Windows linker prerequisites
in [Odin's installation guide](https://odin-lang.org/docs/install/).
The tested native setup uses Visual Studio's **Desktop development with C++**
workload. These are development requirements; people playing exported games do
not need them.

On Apple Silicon macOS, install Xcode Command Line Tools with `xcode-select --install` in
place of the Windows linker prerequisites. Use a native terminal and mise
installation for your Mac's architecture. The project builds its pinned SDL3
dependency; a separate Homebrew SDL installation is unnecessary.

Open a terminal in a folder where you keep projects, then run:

```text
git clone https://github.com/ctxshift/bytorio.git
cd bytorio
mise trust
mise install
mise exec -- npm ci
mise run byt -- --help
```

`mise trust` allows this checkout's tool configuration to run. Review the source
before trusting it. Mise installs the pinned compilers and build tools; npm
installs the JavaScript dependencies. The first setup needs an internet
connection and may take a while. The final command should print `Usage: byt`.

## Create and run a game

Stay in the Bytorio source folder and run:

```text
mise run byt -- new ../my-game
mise run byt -- check ../my-game
mise run byt -- run ../my-game --web
```

This creates a separate `my-game` folder beside the checkout. The first check
also builds the player components; subsequent commands reuse build artifacts.
Open the player URL printed by the last command, then choose **Start game**.
Use the arrow keys to move the sprite and Space to play a sound.
Press Ctrl+C in the terminal to stop the local server.

The rest of the guides use `byt` as shorthand for the full authoring CLI. The
downloadable preview supports only the commands listed above. For this
source setup, replace `byt` with `mise run byt --` and run it from the
Bytorio checkout. Project paths remain relative to your terminal's folder.
For example, `byt pack ../my-game` becomes `mise run byt -- pack ../my-game`.

For Odin, add `--language odin` to `new`; use a different, nonexistent project
folder. To run a native export, use `--native` instead of `--web`.

## Make your first change

Open `my-game/src/main.luau` in a code editor. The starter has three callbacks:

- `init` sets up the game when it starts.
- `update(dt)` changes game state, reads controls and triggers sounds.
- `draw` draws the current state without advancing the game.

Find `byt.clear(byt.rgb(23, 32, 46))` in `draw` and change the three color
values. Save the file, stop the server and run the web command again. The
background should change. Then try changing the movement speed, `90`, in
`update`; keep the multiplication by `dt` so the speed stays tied to game time.

Use [the API reference](../sdk/api.md) to look up drawing and input operations.
The [glossary](../GLOSSARY.md) explains terms such as cartridge, tick and resource.

## Share your game

From the source checkout:

```text
mise run byt -- pack ../my-game
```

The cartridge is `my-game/build/game.png`. Send the original file to someone
with a compatible player. Resizing or re-saving the image can remove the game.
See [PNG cartridges](png-cartridges.md) for cover art and player exports.

## If something goes wrong

| Symptom | What to check |
| --- | --- |
| `mise` is not recognized | Finish the mise installation and open a new terminal. |
| `byt` is not recognized | Use `.\byt.exe` on Windows or `./byt` on macOS from the download folder, or add that folder to your user PATH and reopen the terminal. |
| Mac reports `permission denied` when launching `byt` | Run `chmod +x byt` from the folder containing the executable. |
| Mac reports `bad CPU type in executable` | Download the binary matching your Mac's chip from the table above. |
| macOS blocks the developer | Follow the first-launch instructions in the Mac section above. |
| Preview says a command is unsupported | Use the source CLI below for build/check/run/pack/import/watch. |
| No mise task named `byt` | Run the command from the Bytorio checkout, not from `my-game`. |
| Missing compiler or linker | Complete `mise install` and the platform prerequisites above. |
| Project folder already exists | `new` creates a fresh project; choose another folder or run the existing project. |
| Server port is already in use | Stop the previous server, or add `--port 8081`. |
| No sound | Choose **Start game** and interact with the player; browsers require a gesture to enable audio. |

For console builds, tests and runtime internals, see
[Contributor documentation](contributing.md).

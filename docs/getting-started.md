# Getting started with Bytorio

Bytorio lets you make a small game in Luau or Odin and share it as a PNG
cartridge. Start with Luau if you are new to programming. Both languages use
the same console capabilities.

You can [play the browser demos](https://bytor.io/showcase/) without installing
development tools. Choose **Load game**, then **Start game** to enable sound.

## Installation status

The standalone `byt` installer is not available yet. Creating games currently
requires a source checkout on **Windows x64**, even for browser exports.
The steps below describe that working development setup.

We plan to distribute `byt` as a standalone executable that manages its SDK and
tool dependencies, with mise as an optional way to install it. That release will
not require users to install Bun or Node separately. macOS and Linux authoring
support will be listed when their release packages have been tested.

## Install the development tools

Install [Git](https://git-scm.com/downloads),
[mise](https://mise.jdx.dev/getting-started), and the Windows linker prerequisites
in [Odin's installation guide](https://odin-lang.org/docs/install/).
The tested native setup uses Visual Studio's **Desktop development with C++**
workload. These are development requirements; people playing exported games do
not need them.

Open a terminal in a folder where you keep projects, then run:

```text
git clone https://github.com/ctxshift/free-machine.git
cd free-machine
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

The rest of the guides use the intended installed command, `byt`. For this
source setup, replace that command with `mise run byt --` and run it from the
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
| `byt` is not recognized | The standalone installer is not released; use the source-checkout commands above. |
| No mise task named `byt` | Run the command from the Bytorio checkout, not from `my-game`. |
| Missing compiler or linker | Complete `mise install` and the Windows linker prerequisites above. |
| Project folder already exists | `new` creates a fresh project; choose another folder or run the existing project. |
| Server port is already in use | Stop the previous server, or add `--port 8081`. |
| No sound | Choose **Start game** and interact with the player; browsers require a gesture to enable audio. |

For console builds, tests and runtime internals, see
[Contributor documentation](contributing.md).

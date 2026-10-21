# Example projects

Each directory is a nested mise project. Its `mise.toml` owns build, startup,
generation and game-specific measurement tasks. Language variants, shared art,
launchers and tools live beside that configuration. Generated exports and game
reports go into its ignored `build/` directory.

From a project's directory:

```text
mise run build
mise run serve
```

From anywhere in this repository, use its monorepo task path:

```text
mise run //examples/kart3d:build
mise run //examples/kart3d:serve
mise run validate //examples/kart3d:test
```

| Project | Purpose | Browser port |
| --- | --- | ---: |
| [kart3d](kart3d/README.md) | Eight-kart perspective racer in both SDKs | 8082 |
| [rpg](rpg/README.md) | Sprite RPG in both SDKs | 8083 |
| [racing](racing/README.md) | Earlier span-rendered racer in both SDKs | 8084 |
| [models](models/README.md) | Imported rigid mesh in both SDKs | 8085 |
| [billboards](billboards/README.md) | Billboard and alpha-cutout garden | 8086 |
| [hello](hello/README.md) | Minimal native/browser sprite and sound | 8087 |
| [resources](resources/README.md) | Explicit graphics and audio resources | 8088 |
| [effects](effects/README.md) | Depth-tested smoke and additive particles | 8089 |

The projects inherit pinned tools and shared dependency tasks from the root.
Build/check tasks use the repository as their explicit working directory when
calling shared SDK tooling; startup tasks serve their local `build/` directory.
The root validation suite includes example integration checks alongside SDK and
runtime conformance. Library tools under `tools/` provide reusable SDK operations;
`_shared/` contains the packaging helpers for the two earlier ABI 1 games.

The [voxel rendering experiment](../experiments/voxel-resolution/README.md) also
owns a nested mise configuration. Its performance and conformance workloads
retain their existing shared `build/compact-3d/` exports and measurement paths.

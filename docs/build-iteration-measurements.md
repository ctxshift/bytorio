# Build iteration measurements

Splitting the player artifacts and narrowing trace-harness inputs removes most
compilation from browser-only edits. It does not make the compiler faster or
skip test execution.

## Results

Measured on Windows x64 on 2026-10-21 with Node 24.19.0, mise 2026.10.15 and
Odin dev-2026-10 (84bc3fc). The baseline was commit `f5833eb`. Each row times
`build:odin` followed by the resources, graphics and audio trace dependency tasks.
Tasks and their children run serially with `--jobs 1` in both versions.

| Case | Baseline | Split tasks | Odin builds, before → after |
| --- | ---: | ---: | ---: |
| Forced rebuild | 234.43 s | 234.92 s | 16 → 16 |
| Unchanged inputs | 2.42 s | 2.37 s | 0 → 0 |
| Browser `player.js` edit | 233.27 s | 6.59 s | 16 → 0 |
| Unrelated renderer test edit | Excluded | 2.42 s | — → 0 |

The browser edit is approximately **35 times faster**, a **97% reduction** in
this build-dependency sequence. Cold and unchanged times are essentially equal
at this measurement resolution. These are single samples, not statistical
confidence intervals or full-validation speedups.

A shared resources-package edit measured 251.52 seconds / 16 builds before and
248.61 seconds / 6 builds after the split. That after sample preceded the final
aggregate shortcut; leaf compiler tasks were the same. Six expensive host/trace
compiles dominate this case, so there is no demonstrated material time saving.

The first baseline test-only trial also saw a restored browser input from the
preceding trial. It is excluded as an isolated before/after comparison. The final
helper primes original inputs before each edited trial, outside the timed region,
so restoring the preceding edit cannot contaminate it.

## Reproduce

Use an isolated checkout with pinned tools installed and no competing builds,
tests or edits:

```text
mise run bench:build-tasks -- --label comparison
mise run bench:build-tasks -- --label quick --cases warm,browser,unrelated-test
```

The helper temporarily appends a harmless comment to each selected source and
restores its original bytes and timestamps in `finally`. Labels must be new;
existing results are never overwritten. Retained per-task logs, command journals
and the source-fingerprinted report are under
`build/iteration-measurements/<label>/`. A failed, interrupted or stale report is
not a completed measurement. Cold means forced project artifact compilation;
it does not include tool downloads, dependency installation or the Luau build.

To measure an older revision, copy `tools/measure-build-tasks.mjs` into `tools/`
of a separate checkout as an untracked helper, then invoke it using
`mise exec -- node tools/measure-build-tasks.mjs --label baseline`. Use the same
mise version and case selection. The original baseline capture used an earlier
helper; its cold, unchanged and browser trials are comparable, while the later
test-only trial is excluded above.

The implementation run retained `baseline`, `split` and `final` series. The final
series passed with equal initial/final source fingerprints. Its sixteen compiler
commands matched baseline sources and flags after excluding output paths and
argument ordering. Raw journals include local diagnostic paths and remain
ignored rather than becoming tracked records. No heavy external compiler was
observed during process snapshots; those snapshots are not continuous monitoring.

## Coverage and remaining cost

All sixteen existing aggregate conformance suites remain, as do drawing and
executor-cache gates. `test:build-tasks` adds import/shader input coverage,
support-file output inventory, forced and missing-output rebuilds, added/deleted
source detection, and affected-artifact checks against the real mise scheduler
using inexpensive substitute commands. It also checks the aggregate inventory
so a new leaf input cannot silently bypass the warm-build shortcut.

Run `mise run validate` for complete lint, formatting, generated-code and
conformance checks, and `mise run validate test:textured3d:gpu` for the additional
native/browser GPU qualification. Test results are never cached. Production
optimization flags, fault fixtures, assertions and native/browser combinations
are preserved. The scheduler regression suite itself adds approximately one
minute to full validation; use focused validation during normal iteration.

Further savings for shared-runtime changes require a separate compiler or
architecture investigation. This task split addresses unnecessary rebuilds.

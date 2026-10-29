# Development workflow

Read [development](docs/development.md) for pinned tools, commands and validation
reports, and [language examples](docs/language-examples.md) before adding SDK or
resource code. Consult the current specification and implementation plan for the
feature's contract and acceptance criteria.

- Use mise tasks. Keep project commands in `mise.toml`, dependency tasks in
  `.mise/tasks/`, and orchestration that needs code in JavaScript. Do not add
  PowerShell or Python project scripts.
- Implement small compileable slices. For a resource feature, establish the
  contract and one lifecycle through both SDKs before expanding behavior.
  Reuse existing test setup rather than guessing compiler or test APIs.
- Write readable source before running formatters: separate imports, constants,
  state and functions; use one statement per line and names that explain intent.
  Do not repair source layout with ad hoc regular-expression formatters.
- Put shared protocol values in the existing schemas and regenerate them. Name
  constants by meaning; identical numbers do not necessarily share a meaning.
- During iteration, run the smallest affected checks. For visual changes, show
  the actual preview and check the requested behavior before completion validation.
  Follow [preview-first](docs/development.md#preview-first) for staged exports and
  [checks](docs/development.md#checks) for scope selection, committed changes and
  cancellation. Local completion uses affected checks; shared or unclassified code
  selects full validation. CI and release workflows retain their complete gates.
- Let mise reuse compiled artifacts; follow
  [cache decisions](docs/development.md#iteration-and-cache-decisions) when changing
  dependencies or diagnosing stale outputs.
- Read the runner's report and the failing task's retained log. A stale,
  interrupted or failed report is not a pass. Do not overlap benchmark runs with
  heavy builds/tests or repeatedly read unchanged logs.
- Before final validation, review ownership, bounds, rollback, compatibility and
  public API ergonomics. Cross-host parity complements independent expected
  results; it does not replace them.
- Report the checks actually completed and remaining integration limits.
  Keep each commit focused on a verified step.

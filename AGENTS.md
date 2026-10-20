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
- Run focused `mise run validate <task...>` checks during iteration. Before
  completion, finish edits and run `mise run validate` for the complete gates.
  Preserve coverage; a focused pass does not substitute for final conformance.
- Read the runner's report and the failing task's retained log. A stale,
  interrupted or failed report is not a pass. Do not overlap benchmark runs with
  heavy builds/tests or repeatedly read unchanged logs.
- Before final validation, review ownership, bounds, rollback, compatibility and
  public API ergonomics. Cross-host parity complements independent expected
  results; it does not replace them.
- Report the checks actually completed and remaining integration limits.
  Keep each commit focused on a verified step.

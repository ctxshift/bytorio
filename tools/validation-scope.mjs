import { execFileSync } from "node:child_process";

export const fullTasks = [
  "lint",
  "format:check",
  "generate:check",
  "test",
  "test:drawing",
  "test:cache",
  "format:check",
];

// Deliberately small allowlist. Unclassified code selects the complete gate.
const scopes = [
  {
    name: "showcase-exports",
    matches: (file) =>
      [
        "site/catalog.mjs",
        "tools/build-site.mjs",
        "tools/showcase-exports.mjs",
        "tools/showcase-exports.test.mjs",
      ].includes(file),
    tasks: ["build:site", "test:site"],
  },
  {
    name: "cover-assets",
    matches: (file) =>
      ["site/assets/brand/cartridge.png", "site/assets/brand/logo.png"].includes(file),
    tasks: ["test:cover", "test:cli", "test:site"],
  },
  {
    name: "site",
    matches: (file) =>
      (file.startsWith("site/") && !file.startsWith("site/deploy/")) ||
      ["tools/verify-site.mjs", "tools/serve-site.mjs", "tools/capture-site.mjs"].includes(file),
    tasks: ["test:site"],
  },
  {
    name: "player-ui",
    matches: (file) =>
      [
        "runtime/odin/web/web-player.js",
        "runtime/odin/web/player.html",
        "runtime/odin/web/player-config.js",
        "runtime/odin/web/player-input.js",
        "tools/player-input.test.mjs",
        "tools/verify-web-player.mjs",
      ].includes(file),
    tasks: ["test:web-player", "test:web-runtime", "test:site", "test:player-export"],
  },
  {
    name: "cover",
    matches: (file) => file === "tools/cli/cover.mjs" || file === "tools/cli/cover.test.mjs",
    tasks: ["test:cover", "test:cli"],
  },
  {
    name: "documentation",
    matches: (file) =>
      file.endsWith(".md") &&
      (!file.includes("/") ||
        ["docs/", "sdk/", ".agents/"].some((prefix) => file.startsWith(prefix))),
    tasks: ["test:site"],
  },
];

export function changedFiles(cwd, base = "HEAD") {
  const git = (args) => execFileSync("git", args, { cwd, encoding: "utf8" });
  // Resolve the revision before passing it to diff; renames expose both paths.
  const revision = git(["rev-parse", "--verify", "--end-of-options", `${base}^{commit}`]).trim();
  return [
    ...new Set(
      [
        ...git(["diff", "--name-only", "--no-renames", "-z", revision, "--"]).split("\0"),
        ...git(["diff", "--cached", "--name-only", "--no-renames", "-z", revision, "--"]).split(
          "\0",
        ),
        ...git(["ls-files", "--others", "--exclude-standard", "-z"]).split("\0"),
      ].filter(Boolean),
    ),
  ].sort();
}

export function affectedPlan(files) {
  const matches = files.map((file) => ({
    file,
    scope: scopes.find((scope) => scope.matches(file))?.name ?? "full",
  }));
  const unknown = matches.filter(({ scope }) => scope === "full");
  const selected = scopes.filter((scope) => matches.some((match) => match.scope === scope.name));
  const focused = [...new Set(selected.flatMap((scope) => scope.tasks))];
  return {
    mode: unknown.length ? "full" : "affected",
    files: matches,
    reason: unknown.length
      ? "Unclassified or shared code requires full validation"
      : files.length
        ? "Known change scopes; relevant integration checks run first"
        : "No changes against the selected base",
    tasks: unknown.length
      ? [...focused, ...fullTasks]
      : files.length
        ? [...focused, "lint", "format:check"]
        : [],
  };
}

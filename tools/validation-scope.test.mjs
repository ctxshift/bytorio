import assert from "node:assert/strict";
import { test } from "node:test";
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync, mkdirSync, renameSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { affectedPlan, changedFiles } from "./validation-scope.mjs";

test("site and player edits select their integration gates before quality checks", () => {
  assert.deepEqual(affectedPlan(["site/site.js"]).tasks, ["test:site", "lint", "format:check"]);
  const plan = affectedPlan(["runtime/odin/web/web-player.js", "docs/web.md"]);
  assert.equal(plan.mode, "affected");
  assert.equal(plan.tasks[0], "test:web-player");
  assert.equal(plan.tasks.filter((task) => task === "test:site").length, 1);
  assert.ok(!plan.tasks.includes("test"));
});

test("shared code, task definitions and unknown paths fail closed", () => {
  for (const file of [
    "runtime/odin/web/runtime.js",
    "sdk/contract.json",
    "mise.toml",
    "tools/cli/main.ts",
    "tools/new-helper.mjs",
    "site-other/code.js",
    "site/deploy/Dockerfile",
    "tests/fixtures/generated.md",
  ]) {
    const plan = affectedPlan([file]);
    assert.equal(plan.mode, "full", file);
    assert.ok(plan.tasks.includes("test"), file);
  }
  assert.deepEqual(affectedPlan([]).tasks, []);
  assert.equal(affectedPlan(["tools/cli/cover.mjs"]).tasks[0], "test:cover");
  assert.equal(affectedPlan(["site/assets/brand/logo.png"]).tasks[0], "test:cover");
  assert.equal(affectedPlan(["site/catalog.mjs"]).tasks[0], "build:site");
});

test("selection includes staged, unstaged, untracked and both rename paths", () => {
  const cwd = mkdtempSync(join(tmpdir(), "validation-scope-"));
  const git = (...args) => execFileSync("git", args, { cwd, stdio: "pipe" });
  git("init");
  mkdirSync(join(cwd, "site"));
  writeFileSync(join(cwd, "shared.js"), "original");
  writeFileSync(join(cwd, "staged-only.js"), "original");
  git("add", ".");
  git("-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-m", "initial");
  renameSync(join(cwd, "shared.js"), join(cwd, "site", "moved.js"));
  git("add", ".");
  writeFileSync(join(cwd, "site", "moved.js"), "edited");
  writeFileSync(join(cwd, "new.md"), "notes");
  assert.deepEqual(changedFiles(cwd), ["new.md", "shared.js", "site/moved.js"]);
  assert.equal(affectedPlan(changedFiles(cwd)).mode, "full");
  writeFileSync(join(cwd, "staged-only.js"), "staged change");
  git("add", "staged-only.js");
  writeFileSync(join(cwd, "staged-only.js"), "original");
  assert.ok(changedFiles(cwd).includes("staged-only.js"));
  git("-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-m", "test changes");
  assert.ok(changedFiles(cwd, "HEAD~1").includes("shared.js"));
  assert.throws(() => changedFiles(cwd, "--all"));
});

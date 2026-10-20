import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { runStep, sourceState, validate } from "./validation-runner.mjs";

test("retains large output and preserves a failure after output", async () => {
  const cwd = await mkdtemp(join(tmpdir(), "validation-test-"));
  const log = join(cwd, "output.log");
  const result = await runStep({
    executable: process.execPath,
    args: ["-e", "console.log('x'.repeat(100000)); process.exitCode = 7"],
    cwd,
    log,
    timeoutMs: 10000,
  });
  assert.equal(result.exitCode, 7);
  assert.ok((await readFile(log)).length > 100000);
});

test("reports launch failure and bounds a hung command", async () => {
  const cwd = await mkdtemp(join(tmpdir(), "validation-test-"));
  const missing = await runStep({
    executable: join(cwd, "missing-executable"),
    args: [],
    cwd,
    log: join(cwd, "missing.log"),
    timeoutMs: 1000,
  });
  assert.equal(missing.exitCode, 127);
  const hung = await runStep({
    executable: process.execPath,
    args: ["-e", "setInterval(() => {}, 1000)"],
    cwd,
    log: join(cwd, "hung.log"),
    timeoutMs: 100,
  });
  assert.equal(hung.exitCode, 124);
  assert.equal(hung.timedOut, true);
});

test("fingerprints untracked sources but excludes ignored logs", async () => {
  const cwd = await mkdtemp(join(tmpdir(), "validation-test-"));
  for (const args of [
    ["init"],
    [
      "-c",
      "user.name=Test",
      "-c",
      "user.email=test@example.com",
      "commit",
      "--allow-empty",
      "-m",
      "initial",
    ],
  ]) {
    assert.equal(spawnSync("git", args, { cwd }).status, 0);
  }
  await writeFile(join(cwd, ".gitignore"), "*.log\n");
  const initial = sourceState(cwd);
  await writeFile(join(cwd, "output.log"), "ignored");
  assert.equal(sourceState(cwd).fingerprint, initial.fingerprint);
  await writeFile(join(cwd, "example.txt"), "first");
  const added = sourceState(cwd);
  assert.notEqual(added.fingerprint, initial.fingerprint);
  await writeFile(join(cwd, "example.txt"), "second");
  assert.notEqual(sourceState(cwd).fingerprint, added.fingerprint);
});

test("stops on failure and rejects results from changing sources", async () => {
  const cwd = await mkdtemp(join(tmpdir(), "validation-test-"));
  for (const args of [
    ["init"],
    [
      "-c",
      "user.name=Test",
      "-c",
      "user.email=test@example.com",
      "commit",
      "--allow-empty",
      "-m",
      "initial",
    ],
  ]) {
    assert.equal(spawnSync("git", args, { cwd }).status, 0);
  }
  await writeFile(join(cwd, ".gitignore"), "/build/\n");
  const visited = [];
  const options = { cwd, tasks: ["first", "second"], mise: "unused", notify: () => {} };
  const failed = await validate({
    ...options,
    execute: async (step) => {
      visited.push(step.args.at(-1));
      return runStep({ ...step, executable: process.execPath, args: ["-e", "process.exit(9)"] });
    },
  });
  assert.equal(failed.status, "failed");
  assert.deepEqual(visited, ["first"]);
  assert.equal(failed.steps[0].exitCode, 9);

  const stale = await validate({
    ...options,
    tasks: ["first"],
    execute: async (step) => {
      await writeFile(join(cwd, "changed.txt"), "changed while validating");
      return runStep({
        ...step,
        executable: process.execPath,
        args: ["-e", "console.log('passed')"],
      });
    },
  });
  assert.equal(stale.status, "stale");
  assert.equal(stale.sourceChanged, true);
  assert.equal(stale.steps[0].exitCode, 0);

  await assert.rejects(validate({ ...options, tasks: ["validate"] }), /non-recursive/);
});

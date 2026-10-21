import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { odinUnitTests } from "./odin-unit-tests.mjs";

test("shares only successful identical checks within one run and source state", () => {
  const cwd = mkdtempSync(join(tmpdir(), "unit-checks-"));
  const calls = [];
  const options = {
    cwd,
    compiler: "fixture-compiler",
    scope: join(cwd, "first-run"),
    fingerprint: "first-source",
    execute: (compiler, args) => {
      calls.push({ compiler, args });
      return { status: 0, stdout: "all assertions passed", stderr: "diagnostic" };
    },
  };
  const check = (overrides = {}, suite = "tests/3d") =>
    odinUnitTests(suite, join(cwd, "standalone.exe"), { ...options, ...overrides });
  const first = check();
  assert.equal(check(), first);
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0].args.slice(0, 3), ["test", "tests/3d", "-o:none"]);
  check({ fingerprint: "edited-source" });
  check({ scope: join(cwd, "next-run") });
  check({}, "tests/audio");
  check({ compiler: "other-compiler" });
  check({ scope: null });
  check({ scope: null });
  assert.equal(calls.length, 7);
});

test("a failure or launch error never suppresses a later attempt", () => {
  const cwd = mkdtempSync(join(tmpdir(), "unit-failure-"));
  let calls = 0;
  const options = {
    cwd,
    compiler: "fixture-compiler",
    scope: cwd,
    fingerprint: "same-source",
    execute: () => {
      calls++;
      if (calls === 1) {
        return { status: 1, stdout: "assertion failed" };
      }
      if (calls === 2) {
        return { error: new Error("launch failed") };
      }
      return { status: 0, stdout: "passed" };
    },
  };
  const check = () => odinUnitTests("tests/3d", join(cwd, "unit.exe"), options);
  assert.throws(check, /assertion failed/);
  assert.throws(check, /launch failed/);
  assert.equal(check(), "passed");
  assert.equal(check(), "passed");
  assert.equal(calls, 3);
});

import assert from "node:assert/strict";
import { test } from "node:test";
import { redundantBranchRuns, supersedeBranchValidation } from "./release-ci.mjs";
import { readFileSync } from "node:fs";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

test("only duplicate default-branch pushes are superseded; PR and release checks survive", () => {
  const context = { sha: "a".repeat(40), repository: "example/project", branch: "main" };
  const run = {
    id: 1,
    head_sha: context.sha,
    head_repository: { full_name: context.repository },
    head_branch: "main",
    event: "push",
    path: ".github/workflows/build.yml",
    pull_requests: [],
    status: "in_progress",
  };
  const excluded = [
    { head_sha: "b".repeat(40) },
    { head_branch: "feature" },
    { event: "pull_request" },
    { path: ".github/workflows/release.yml" },
    { status: "completed" },
    { pull_requests: [{ number: 1 }] },
    { head_repository: { full_name: "fork/project" } },
  ].map((override, index) => ({ ...run, id: index + 2, ...override }));
  assert.deepEqual(
    redundantBranchRuns([run, ...excluded], context).map((item) => item.id),
    [1],
  );
});

test("both workflow matrices retain full Windows and Apple Silicon validation", () => {
  for (const file of ["build.yml", "release.yml"]) {
    const source = readFileSync(new URL(`../.github/workflows/${file}`, import.meta.url), "utf8");
    assert.match(source, /platform: windows-x64\s+validation: --full/);
    assert.match(source, /platform: macos-arm64\s+validation: --full/);
    assert.match(source, /platform: macos-x64\s+validation: test:cli/);
    assert.match(source, /run: mise run validate \$\{\{ matrix.validation \}\}/);
  }
});

test("release CI requests cancellation only for matching runs and rejects non-tag callers", async () => {
  const root = await mkdtemp(join(tmpdir(), "release-ci-"));
  const event = join(root, "event.json");
  await writeFile(event, JSON.stringify({ repository: { default_branch: "main" } }));
  const env = {
    GITHUB_EVENT_PATH: event,
    GITHUB_EVENT_NAME: "push",
    GITHUB_REF: "refs/tags/byt-v0.2.0",
    GITHUB_REPOSITORY: "example/project",
    GITHUB_SHA: "a".repeat(40),
    GITHUB_TOKEN: "fixture",
  };
  const calls = [];
  const request = async (url, options) => {
    calls.push({ url, method: options.method ?? "GET" });
    if (options.method === "POST") {
      return new Response(null, { status: 202 });
    }
    return Response.json({
      workflow_runs: [
        {
          id: 12,
          head_sha: env.GITHUB_SHA,
          head_repository: { full_name: env.GITHUB_REPOSITORY },
          head_branch: "main",
          event: "push",
          path: ".github/workflows/build.yml",
          pull_requests: [],
          status: "queued",
        },
      ],
    });
  };
  assert.deepEqual(await supersedeBranchValidation(env, request), [12]);
  assert.equal(calls.length, 2);
  assert.ok(calls[0].url.includes(`head_sha=${env.GITHUB_SHA}`));
  assert.equal(calls[1].url, "https://api.github.com/repos/example/project/actions/runs/12/cancel");
  await assert.rejects(
    supersedeBranchValidation({ ...env, GITHUB_REF: "refs/heads/main" }, request),
    /Only tagged/,
  );
  assert.equal(calls.length, 2);
});

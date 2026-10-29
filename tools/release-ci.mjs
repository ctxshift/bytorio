import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

export function redundantBranchRuns(runs, { sha, repository, branch }) {
  return runs.filter(
    (run) =>
      Number.isSafeInteger(run.id) &&
      run.id > 0 &&
      run.head_sha === sha &&
      run.event === "push" &&
      run.head_branch === branch &&
      run.head_repository?.full_name === repository &&
      run.path === ".github/workflows/build.yml" &&
      Array.isArray(run.pull_requests) &&
      run.pull_requests.length === 0 &&
      ["queued", "in_progress", "pending", "waiting", "requested"].includes(run.status),
  );
}

export async function supersedeBranchValidation(env = process.env, request = fetch) {
  const event = JSON.parse(await readFile(env.GITHUB_EVENT_PATH, "utf8"));
  if (env.GITHUB_EVENT_NAME !== "push" || !/^refs\/tags\/(byt|sdk)-v/.test(env.GITHUB_REF ?? "")) {
    throw new Error("Only tagged release workflows can supersede branch validation");
  }
  const repository = env.GITHUB_REPOSITORY;
  const sha = env.GITHUB_SHA;
  const branch = event.repository?.default_branch;
  if (
    !/^[\w.-]+\/[\w.-]+$/.test(repository ?? "") ||
    !/^[a-f0-9]{40}$/.test(sha ?? "") ||
    !branch
  ) {
    throw new Error("Missing release repository, commit or default branch");
  }
  const root = `${env.GITHUB_API_URL ?? "https://api.github.com"}/repos/${repository}/actions`;
  const headers = {
    Authorization: `Bearer ${env.GITHUB_TOKEN}`,
    Accept: "application/vnd.github+json",
  };
  const cancelled = [];
  for (let page = 1; page <= 10; page++) {
    const response = await request(
      `${root}/workflows/build.yml/runs?head_sha=${sha}&event=push&per_page=100&page=${page}`,
      {
        headers,
        signal: AbortSignal.timeout(15000),
      },
    );
    if (!response.ok) {
      throw new Error(`Cannot inspect duplicate CI: HTTP ${response.status}`);
    }
    const data = await response.json();
    for (const run of redundantBranchRuns(data.workflow_runs, { sha, repository, branch })) {
      const result = await request(`${root}/runs/${run.id}/cancel`, {
        method: "POST",
        headers,
        signal: AbortSignal.timeout(15000),
      });
      if (!result.ok && result.status !== 409) {
        throw new Error(`Cannot cancel duplicate CI: HTTP ${result.status}`);
      }
      if (result.ok) {
        cancelled.push(run.id);
      }
    }
    if (data.workflow_runs.length < 100) {
      return cancelled;
    }
  }
  throw new Error("Duplicate CI listing exceeded page limit");
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  console.log(JSON.stringify({ supersededBranchRuns: await supersedeBranchValidation() }));
}

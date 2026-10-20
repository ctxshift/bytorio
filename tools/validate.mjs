import { repo } from "./toolchain.mjs";
import { spawnSync } from "node:child_process";
import { validate } from "./validation-runner.mjs";

const full = [
  "lint",
  "format:check",
  "generate:check",
  "test",
  "test:drawing",
  "test:cache",
  "format:check",
];
const selected = process.argv.slice(2);
if (selected.includes("--help")) {
  console.log(
    "Usage: mise run validate [--full | task ...]\nDefaults to all quality and conformance gates. Logs: build/validation/<run>/",
  );
} else {
  const tasks =
    !selected.length || (selected.length === 1 && selected[0] === "--full") ? full : selected;
  const mise = process.env.MISE_BIN || "mise";
  // Mise owns the suite inventory. Keep aggregate semantics if it gains setup.
  if (tasks.includes("test")) {
    const result = spawnSync(mise, ["tasks", "info", "test", "--json"], {
      cwd: repo,
      encoding: "utf8",
      timeout: 10000,
    });
    if (result.error || result.status !== 0) {
      throw new Error(result.error?.message || result.stderr);
    }
    const task = JSON.parse(result.stdout);
    if (
      task.run?.length &&
      task.run.every(
        (entry) =>
          typeof entry === "object" &&
          Object.keys(entry).length === 1 &&
          typeof entry.task === "string",
      ) &&
      !task.depends.length &&
      !task.depends_post.length &&
      !task.env.length &&
      !Object.keys(task.tools).length &&
      task.dir === repo &&
      !task.sources.length &&
      !task.outputs.length &&
      !task.skip_if
    ) {
      tasks.splice(tasks.indexOf("test"), 1, ...task.run.map((entry) => entry.task));
    }
  }
  const report = await validate({ cwd: repo, tasks, mise });
  process.exitCode = report.status === "passed" ? 0 : 1;
}

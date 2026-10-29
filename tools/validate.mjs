import { repo } from "./toolchain.mjs";
import { spawnSync } from "node:child_process";
import { validate } from "./validation-runner.mjs";
import { affectedPlan, changedFiles, fullTasks } from "./validation-scope.mjs";
import { validationControl } from "./validation-control.mjs";

const selected = process.argv.slice(2);
if (selected.includes("--help")) {
  console.log(
    "Usage: mise run validate [--affected [--base <ref>] | --full | task ...] [--plan]\nDefault: affected changes against HEAD, including untracked files. Unknown code selects full.\n--base includes already committed work. --plan prints selection without running.\n--status <run> | --cancel <run> inspect or cooperatively stop a run. Logs: build/validation/<run>/",
  );
} else if (["--status", "--cancel"].includes(selected[0])) {
  if (selected.length !== 2) {
    throw new Error("Expected a validation run directory name");
  }
  console.log(
    JSON.stringify(await validationControl(repo, selected[1], selected[0] === "--cancel"), null, 2),
  );
} else {
  const dryRun = selected.includes("--plan");
  const args = selected.filter((arg) => arg !== "--plan");
  let selection;
  if (!args.length || args[0] === "--affected" || args[0] === "--base") {
    if (args[0] === "--affected") {
      args.shift();
    }
    if (args.length && (args.length !== 2 || args[0] !== "--base")) {
      throw new Error("Expected --affected [--base <ref>]");
    }
    const base = args[1] ?? "HEAD";
    selection = { ...affectedPlan(changedFiles(repo, base)), base };
  } else if (args.length === 1 && args[0] === "--full") {
    selection = { mode: "full", tasks: [...fullTasks] };
  } else {
    if (args.some((arg) => arg.startsWith("--"))) {
      throw new Error("Unknown validation option");
    }
    selection = { mode: "explicit", tasks: args };
  }
  const tasks = [...selection.tasks];
  console.log(JSON.stringify(selection, null, 2));
  if (dryRun || !tasks.length) {
    if (!tasks.length) {
      console.log(
        "No checks selected; this is not a validation pass. Use --base for committed work.",
      );
    }
    process.exit(0);
  }
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
  // Focused prerequisites may also occur in the full aggregate. Run them once,
  // retaining the final formatting check that detects generator side effects.
  const seen = new Set();
  const uniqueTasks = tasks.filter((task) => {
    if (task === "format:check") {
      return true;
    }
    if (seen.has(task)) {
      return false;
    }
    seen.add(task);
    return true;
  });
  const report = await validate({ cwd: repo, tasks: uniqueTasks, mise, selection });
  process.exitCode = report.status === "passed" ? 0 : 1;
}

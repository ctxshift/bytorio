import { spawn, spawnSync } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { closeSync, lstatSync, openSync, readFileSync, readlinkSync } from "node:fs";
import { mkdir, rename, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

export function sourceState(cwd) {
  function git(args) {
    const result = spawnSync("git", args, { cwd, encoding: "utf8" });
    if (result.error || result.status !== 0) {
      throw new Error(result.error?.message || result.stderr);
    }
    return result.stdout;
  }

  const files = [
    ...new Set(
      git(["ls-files", "-z", "--cached", "--others", "--exclude-standard"])
        .split("\0")
        .filter(Boolean),
    ),
  ].sort();
  const hash = createHash("sha256");
  for (const file of files) {
    hash.update(file + "\0");
    const path = resolve(cwd, file);
    try {
      const stat = lstatSync(path);
      const contents = stat.isSymbolicLink() ? readlinkSync(path) : readFileSync(path);
      hash.update(stat.isSymbolicLink() ? "link\0" : "file\0");
      hash.update(createHash("sha256").update(contents).digest());
    } catch (error) {
      if (error.code !== "ENOENT") {
        throw error;
      }
      hash.update("deleted\0");
    }
  }
  return {
    revision: git(["rev-parse", "HEAD"]).trim(),
    fingerprint: hash.digest("hex"),
    files: files.length,
  };
}

export async function runStep({ executable, args, cwd, log, timeoutMs }) {
  const started = Date.now();
  const fd = openSync(log, "w");
  let timer;
  let timedOut = false;
  let launchError;
  try {
    const child = spawn(executable, args, {
      cwd,
      stdio: ["ignore", fd, fd],
      windowsHide: true,
      detached: process.platform !== "win32",
    });
    timer = setTimeout(() => {
      timedOut = true;
      if (!child.pid) {
        return;
      }
      if (process.platform === "win32") {
        spawnSync("taskkill", ["/PID", String(child.pid), "/T", "/F"], { windowsHide: true });
      } else {
        try {
          process.kill(-child.pid, "SIGKILL");
        } catch (error) {
          if (error.code !== "ESRCH") {
            launchError = error.message;
          }
        }
      }
    }, timeoutMs);
    return await new Promise((done) => {
      child.on("error", (error) => {
        launchError = error.message;
      });
      child.on("close", (code, signal) =>
        done({
          exitCode: timedOut ? 124 : launchError ? 127 : (code ?? 1),
          signal,
          timedOut,
          error: launchError ?? null,
          durationMs: Date.now() - started,
        }),
      );
    });
  } finally {
    clearTimeout(timer);
    closeSync(fd);
  }
}

export async function validate({
  cwd,
  tasks,
  mise,
  timeoutMs = 30 * 60 * 1000,
  notify = console.log,
  execute = runStep,
}) {
  if (
    !tasks.length ||
    tasks.some((task) => !/^[a-z][a-z0-9:-]*$/.test(task) || task.startsWith("validate"))
  ) {
    throw new Error("Select at least one non-recursive mise task");
  }
  const directory = `build/validation/${new Date().toISOString().replaceAll(":", "-")}-${randomUUID()}`;
  await mkdir(resolve(cwd, directory), { recursive: true });
  const report = {
    version: 1,
    startedAt: new Date().toISOString(),
    node: process.version,
    platform: process.platform,
    source: sourceState(cwd),
    status: "running",
    steps: [],
  };
  async function save() {
    const target = resolve(cwd, directory, "report.json");
    await writeFile(target + ".tmp", JSON.stringify(report, null, 2) + "\n");
    await rename(target + ".tmp", target);
  }
  await save();
  notify(`Validation report: ${directory}/report.json`);
  try {
    for (const [index, task] of tasks.entries()) {
      const log = `${directory}/${String(index + 1).padStart(2, "0")}-${task.replaceAll(":", "-")}.log`;
      notify(`[${index + 1}/${tasks.length}] ${task}`);
      const before = sourceState(cwd);
      const result = await execute({
        executable: mise,
        args: ["run", task],
        cwd,
        log: resolve(cwd, log),
        timeoutMs,
      });
      const after = sourceState(cwd);
      report.steps.push({ task, log, before, after, ...result });
      notify(
        `${task}: ${result.exitCode === 0 ? "PASS" : "FAIL"} (${(result.durationMs / 1000).toFixed(1)}s); ${log}`,
      );
      await save();
      if (result.exitCode !== 0) {
        report.status = "failed";
        break;
      }
    }
    report.finalSource = sourceState(cwd);
    report.sourceChanged =
      report.source.fingerprint !== report.finalSource.fingerprint ||
      report.steps.some(
        (step) =>
          step.before.fingerprint !== report.source.fingerprint ||
          step.after.fingerprint !== report.source.fingerprint,
      );
    if (report.status === "running") {
      report.status = report.sourceChanged ? "stale" : "passed";
    }
  } catch (error) {
    report.status = "failed";
    report.error = error.message;
  }
  report.finishedAt = new Date().toISOString();
  await save();
  notify(`Validation ${report.status}: ${directory}/report.json`);
  return report;
}

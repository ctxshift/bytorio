import { spawn, spawnSync } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { closeSync, existsSync, lstatSync, openSync, readFileSync, readlinkSync } from "node:fs";
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

export async function runStep({
  executable,
  args,
  cwd,
  log,
  timeoutMs,
  env = process.env,
  signal,
}) {
  const started = Date.now();
  const fd = openSync(log, "w");
  let timer;
  let timedOut = false;
  let launchError;
  let interrupted = false;
  let stopped = false;
  let interrupt;
  try {
    const child = spawn(executable, args, {
      cwd,
      env,
      stdio: ["ignore", fd, fd],
      windowsHide: true,
      detached: process.platform !== "win32",
    });
    function stop() {
      if (!child.pid || stopped) {
        return;
      }
      stopped = true;
      if (process.platform === "win32") {
        const result = spawnSync("taskkill", ["/PID", String(child.pid), "/T", "/F"], {
          windowsHide: true,
          timeout: 10000,
        });
        if (result.error || result.status !== 0) {
          child.kill();
        }
      } else {
        try {
          process.kill(-child.pid, "SIGKILL");
        } catch (error) {
          if (error.code !== "ESRCH") {
            launchError = error.message;
          }
        }
      }
    }
    interrupt = () => {
      interrupted = true;
      stop();
    };
    process.once("SIGINT", interrupt);
    process.once("SIGTERM", interrupt);
    signal?.addEventListener("abort", interrupt, { once: true });
    if (signal?.aborted) {
      interrupt();
    }
    timer = setTimeout(() => {
      timedOut = true;
      stop();
    }, timeoutMs);
    return await new Promise((done) => {
      child.on("error", (error) => {
        launchError = error.message;
      });
      child.on("close", (code, signal) =>
        done({
          exitCode: interrupted ? 130 : timedOut ? 124 : launchError ? 127 : (code ?? 1),
          signal,
          timedOut,
          interrupted,
          error: launchError ?? null,
          durationMs: Date.now() - started,
        }),
      );
    });
  } finally {
    clearTimeout(timer);
    if (interrupt) {
      process.removeListener("SIGINT", interrupt);
      process.removeListener("SIGTERM", interrupt);
      signal?.removeEventListener("abort", interrupt);
    }
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
  selection = null,
}) {
  if (
    !tasks.length ||
    tasks.some((task) => {
      const name = task.startsWith("//") ? task.slice(task.indexOf(":") + 1) : task;
      return (
        !/^(?:\/\/(?:[a-zA-Z0-9_-]+\/)*[a-zA-Z0-9_-]*:)?[a-z][a-z0-9:-]*$/.test(task) ||
        name.startsWith("validate")
      );
    })
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
    pid: process.pid,
    selection,
    source: sourceState(cwd),
    unitTests: `${directory}/unit-tests`,
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
  const controller = new AbortController();
  const interrupt = () => controller.abort();
  process.once("SIGINT", interrupt);
  process.once("SIGTERM", interrupt);
  const cancellation = setInterval(() => {
    if (existsSync(resolve(cwd, directory, "cancel"))) {
      controller.abort();
    }
  }, 250);
  try {
    for (const [index, task] of tasks.entries()) {
      if (controller.signal.aborted) {
        report.status = "interrupted";
        break;
      }
      report.currentTask = task;
      await save();
      const log = `${directory}/${String(index + 1).padStart(2, "0")}-${task.replaceAll(/[^a-zA-Z0-9_-]/g, "-")}.log`;
      notify(`[${index + 1}/${tasks.length}] ${task}`);
      const before = sourceState(cwd);
      if (before.fingerprint !== report.source.fingerprint) {
        report.status = "stale";
        break;
      }
      const commands = log.replace(/\.log$/, ".commands.jsonl");
      const browser = log.replace(/\.log$/, ".browser.jsonl");
      await writeFile(resolve(cwd, commands), "");
      await writeFile(resolve(cwd, browser), "");
      const result = await execute({
        executable: mise,
        args: ["run", task],
        cwd,
        log: resolve(cwd, log),
        timeoutMs,
        signal: controller.signal,
        env: {
          ...process.env,
          VALIDATION_COMMAND_TIMINGS: resolve(cwd, commands),
          VALIDATION_UNIT_TESTS: resolve(cwd, report.unitTests),
          VALIDATION_BROWSER_TIMINGS: resolve(cwd, browser),
        },
      });
      const after = sourceState(cwd);
      const browserSummary = {};
      for (const line of readFileSync(resolve(cwd, browser), "utf8").split("\n").filter(Boolean)) {
        const event = JSON.parse(line);
        const phase = (browserSummary[event.phase] ??= { calls: 0, durationMs: 0, failures: 0 });
        phase.calls++;
        phase.durationMs += event.durationMs;
        phase.failures += event.error === null ? 0 : 1;
      }
      report.steps.push({ task, log, commands, browser, browserSummary, before, after, ...result });
      notify(
        `${task}: ${result.exitCode === 0 ? "PASS" : "FAIL"} (${(result.durationMs / 1000).toFixed(1)}s); ${log}`,
      );
      await save();
      if (result.exitCode !== 0) {
        report.status = result.interrupted ? "interrupted" : "failed";
        break;
      }
      if (after.fingerprint !== report.source.fingerprint) {
        report.status = "stale";
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
  } finally {
    clearInterval(cancellation);
    process.removeListener("SIGINT", interrupt);
    process.removeListener("SIGTERM", interrupt);
  }
  report.currentTask = null;
  report.finishedAt = new Date().toISOString();
  await save();
  notify(`Validation ${report.status}: ${directory}/report.json`);
  return report;
}

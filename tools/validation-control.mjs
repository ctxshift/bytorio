import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

export async function validationControl(cwd, id, cancel = false) {
  if (!/^[0-9]{4}-[a-zA-Z0-9.-]+$/.test(id)) {
    throw new Error("Use the run directory name printed by validate (not a path)");
  }
  const directory = resolve(cwd, "build/validation", id);
  const report = JSON.parse(await readFile(resolve(directory, "report.json"), "utf8"));
  let ownerAlive = false;
  if (Number.isInteger(report.pid) && report.pid > 0) {
    try {
      process.kill(report.pid, 0);
      ownerAlive = true;
    } catch (error) {
      if (error.code !== "ESRCH") {
        throw error;
      }
    }
  }
  const cancellationRequested = cancel && report.status === "running" && ownerAlive;
  if (cancellationRequested) {
    // The owning runner observes this file and stops only its own child tree.
    await writeFile(resolve(directory, "cancel"), "Cancellation requested\n");
  }
  return {
    run: id,
    status: report.status === "running" && !ownerAlive ? "incomplete" : report.status,
    ownerAlive,
    currentTask: report.currentTask ?? null,
    completed: report.steps.length,
    cancellationRequested,
  };
}

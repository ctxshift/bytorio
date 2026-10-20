import { repo } from "./toolchain.mjs";
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
  const report = await validate({ cwd: repo, tasks, mise: process.env.MISE_BIN || "mise" });
  process.exitCode = report.status === "passed" ? 0 : 1;
}

import { readFile } from "node:fs/promises";
import { checkGame } from "../sdk/check.mjs";
import { runCheckProcess } from "../sdk/check-process.mjs";

try {
  if (process.argv[2] === "--check-worker") {
    await runCheckProcess();
  } else {
    const payload = JSON.parse(await readFile(process.argv[2], "utf8"));
    await checkGame(payload, { args: ["--check-worker"] });
    console.log("Checked packaged game");
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}

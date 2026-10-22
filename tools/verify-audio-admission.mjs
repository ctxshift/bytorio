import assert from "node:assert/strict";
import { mkdir, readFile, writeFile, copyFile } from "node:fs/promises";
import { resolve } from "node:path";
import { once } from "node:events";
import { createHash, randomUUID } from "node:crypto";
import { createProject, buildProject } from "./sdk/project.mjs";
import { chromium } from "./browser-timing.mjs";
import { serve } from "./serve.mjs";

const root = resolve("build/audio-admission-verification", randomUUID());
const project = resolve(root, "fixture");
await mkdir(root, { recursive: true });
await createProject(project, "odin");
await copyFile("tests/audio-admission/game.odin", resolve(project, "src/main.odin"));
await copyFile("tests/ogg/fixtures/tone.ogg", resolve(project, "tone.ogg"));
const manifest = JSON.parse(await readFile(resolve(project, "console.json")));
Object.assign(manifest, {
  sdk: "0.7.0",
  profile: "ogg-streaming-preview-1",
  content: [{ id: 1, path: "tone.ogg" }],
});
await writeFile(resolve(project, "console.json"), JSON.stringify(manifest, null, 2));
await buildProject(project);
const web = resolve(project, "build/web");
const worker = await readFile(resolve(web, "worker.js"), "utf8");
const observer = await readFile("tests/audio-admission/observer.js", "utf8");
const gate = "await waitForAudioCapacity();";
assert.equal(worker.split(gate).length, 2, "Exactly one normal update admission seam");
await writeFile(resolve(web, "admission-worker.js"), `${worker}\n${observer}`);
await writeFile(
  resolve(web, "admission-red-worker.js"),
  `${worker.replace(gate, "/* Regression baseline: admission gate intentionally omitted. */")}\n${observer}`,
);
await copyFile("tests/audio-admission/browser.js", resolve(web, "admission-test.js"));
await writeFile(
  resolve(web, "admission.html"),
  "<!doctype html><title>Audio admission regression</title>",
);
const server = serve(web, 0);
await once(server, "listening");
const report = {
  status: "running",
  workerSha256: createHash("sha256").update(worker).digest("hex"),
  scope:
    "Actual SDK Ogg guest, resource producer, browser worker, transferable-buffer credits and audio.wasm mixer. Read-only observer appended to copied workers. RED copy omits only the normal update admission await; production files are unchanged.",
  cases: [],
};
let browser;
try {
  browser = await chromium.launch({ channel: process.env.PLAYER_BROWSER_CHANNEL || undefined });
  const page = await browser.newPage();
  await page.goto(`http://127.0.0.1:${server.address().port}/admission.html`);
  for (const baseline of [true, false]) {
    const result = await page.evaluate(async (baseline) => {
      const { verifyAdmission } = await import("./admission-test.js");
      return verifyAdmission(baseline);
    }, baseline);
    report.cases.push(result);
  }
  report.status = "passed";
} finally {
  await browser?.close();
  server.closeAllConnections();
  await new Promise((accept) => server.close(accept));
  await writeFile(resolve(root, "report.json"), JSON.stringify(report, null, 2) + "\n");
  console.log(`Audio admission ${report.status}: ${root}`);
}

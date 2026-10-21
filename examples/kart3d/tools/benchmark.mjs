import assert from "node:assert/strict";
import { once } from "node:events";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { relative, resolve } from "node:path";
import { randomUUID } from "node:crypto";
import { chromium } from "../../../tools/browser-timing.mjs";
import { serve } from "../../../tools/serve.mjs";
import { run } from "../../../tools/toolchain.mjs";
import { course } from "./course.mjs";
import * as policy from "../../../runtime/odin/web/policy.js";

const root = resolve("examples/kart3d/build/benchmarks", randomUUID());
await mkdir(root, { recursive: true });
const imports = { env: { sin: Math.sin } };
const game = (
  await WebAssembly.instantiate(
    await readFile("examples/kart3d/build/odin/build/web/game.wasm"),
    imports,
  )
).instance.exports;
const runtime = (
  await WebAssembly.instantiate(
    await readFile("examples/kart3d/build/odin/build/web/runtime.wasm"),
    imports,
  )
).instance.exports;
game._initialize?.();
runtime.runtime_init();
policy.configureResources(game, runtime);
game.game_init();
policy.submitResources(game, runtime);
const masks = [];
for (let i = 0; i < 300; i++) {
  const s = new Int32Array(game.memory.buffer, game.game_inspect(), 26);
  const curve = course[Math.floor(s[2] / 1024) % 96][5];
  const correction =
    Math.max(-35, Math.min(35, -s[3] / 14)) - s[4] + Math.floor((curve * s[5]) / 1024);
  const mask = 4 | (correction > 1 ? 2 : correction < -1 ? 1 : 0);
  masks.push(mask);
  policy.deliverResources(game, runtime);
  game.game_update(mask, 0, 0, 0);
  policy.checkExecutor(game);
  policy.submitResources(game, runtime);
}
const input = resolve(root, "start.inputs");
await writeFile(input, masks.join("\n") + "\n");
const server = serve(".", 0);
await once(server, "listening");
const browser = await chromium.launch({ channel: process.env.PLAYER_BROWSER_CHANNEL || "chrome" });
const report = {
  status: "running",
  recordedAt: new Date().toISOString(),
  method: {
    frames: 300,
    warmupPasses: 2,
    measuredPasses: 5,
    excludedCountdownFrames: 180,
    scope:
      "Seven sequential race starts. Summaries include 120 moving frames per measured pass, after the countdown. Timings include GPU completion/bitmap creation when selected, exclude diagnostic hashes, main-thread delivery, audio and scanout. Native startup ends at initialization; browser startup includes its first complete frame. Default executor/OS caches are retained. This short rollout does not qualify the complete course or minimum hardware.",
  },
  cases: [],
};
const quantile = (a, q) =>
  [...a].sort((x, y) => x - y)[Math.min(a.length - 1, Math.floor(a.length * q))];
function summary(value) {
  const frames = value.timings.filter((_, i) => i % 300 >= 180);
  const total = frames.map((row) => row.reduce((a, b) => a + b, 0));
  return {
    samples: total.length,
    p50Ms: quantile(total, 0.5),
    p95Ms: quantile(total, 0.95),
    maxMs: Math.max(...total),
    over60HzBudget: total.filter((v) => v > 1000 / 60).length,
    stageP95Ms: frames[0].map((_, i) =>
      quantile(
        frames.map((row) => row[i]),
        0.95,
      ),
    ),
    startup: value.startup,
    memory: value.memory,
    resourceStats: value.resourceStats,
    gpuStats: value.gpuStats,
  };
}
try {
  const page = await browser.newPage();
  for (const language of ["odin", "luau"]) {
    const base = resolve("examples/kart3d/build", language, "build");
    const web = "/" + relative(process.cwd(), resolve(base, "web")).replaceAll("\\", "/");
    await page.goto(`http://127.0.0.1:${server.address().port}${web}/player.html`);
    for (const backend of ["cpu", "gpu"]) {
      const native = JSON.parse(
        run(
          resolve(base, "native/player.exe"),
          [
            "--benchmark",
            input,
            "--renderer",
            backend,
            ...(backend === "gpu" ? ["--gpu-meshes"] : []),
          ],
          { env: { ...process.env, ...(backend === "cpu" ? { SDL_VIDEODRIVER: "dummy" } : {}) } },
        ),
      );
      const result = await page.evaluate(
        async ({ web, masks, backend }) => {
          const worker = new globalThis.Worker(web + "/worker.js", { type: "module" });
          const request = (message, type) =>
            new Promise((resolve, reject) => {
              const timer = setTimeout(() => reject(new Error("Kart benchmark deadline")), 120000);
              worker.onerror = (event) => {
                clearTimeout(timer);
                reject(new Error(event.message));
              };
              worker.onmessage = async ({ data }) => {
                if (data.type === "executor") {
                  const bytes = await (await fetch(web + "/luau-executor.wasm")).arrayBuffer();
                  worker.postMessage({ type: "executor", executor: { bytes } }, [bytes]);
                } else if (data.type === "error") {
                  clearTimeout(timer);
                  reject(new Error(data.error));
                } else if (data.type === type) {
                  clearTimeout(timer);
                  data.bitmap?.close();
                  resolve(data);
                }
              };
              worker.postMessage(message);
            });
          try {
            const ready = await request(
              {
                type: "load",
                gameUrl: globalThis.location.origin + web + "/game.png",
                graphics: { backend, residentMeshes: backend === "gpu" },
              },
              "ready",
            );
            if (ready.graphics.effective !== backend) {
              throw new Error("Wrong benchmark renderer");
            }
            return await request({ type: "benchmark", masks }, "benchmark");
          } finally {
            worker.terminate();
          }
        },
        { web, masks, backend },
      );
      if (backend === "cpu") {
        assert.deepEqual(
          native.traces,
          result.traces,
          `${language}/${backend}: measured replay output`,
        );
      } else {
        assert.deepEqual(
          native.traces.map((x) => x.sounds),
          result.traces.map((x) => x.sounds),
        );
      }
      const row = {
        language,
        backend,
        display: [320, 180],
        ssaa: "off",
        cartridgeBytes: (await readFile(resolve(base, "game.png"))).length,
        native: summary(native),
        browser: summary(result),
      };
      report.cases.push(row);
      await writeFile(
        resolve(root, `${language}-${backend}.json`),
        JSON.stringify({ native, browser: result }, null, 2),
      );
      console.log(
        `${language}/${backend}: native p95 ${row.native.p95Ms.toFixed(2)} ms; browser p95 ${row.browser.p95Ms.toFixed(2)} ms`,
      );
    }
  }
  report.status = "passed";
} finally {
  await browser.close();
  await new Promise((done) => server.close(done));
  await writeFile(resolve(root, "report.json"), JSON.stringify(report, null, 2) + "\n");
}
console.log(`Kart benchmark: ${relative(process.cwd(), root)}`);

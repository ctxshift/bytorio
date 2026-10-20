import assert from "node:assert/strict";
import { once } from "node:events";
import { readFile, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { cpus, platform, release } from "node:os";
import { resolve } from "node:path";
import { execFileSync } from "node:child_process";
import { chromium } from "playwright";
import { serve } from "../../tools/serve.mjs";

const root = resolve("build/compact-3d/resolution/river");
const channel = process.env.PLAYER_BROWSER_CHANNEL || "chrome";
const frames = 120;
const warmup = 45;
const rounds = 3;
const sourceFiles = ["river-live.js", "river-sprite.js", "river-surface.js", "benchmark.mjs"];
const sources = Object.fromEntries(
  await Promise.all(
    sourceFiles.map(async (file) => [
      file,
      createHash("sha256")
        .update(await readFile(new URL(file, import.meta.url)))
        .digest("hex"),
    ]),
  ),
);
const server = serve(root, 0);
await once(server, "listening");
const browser = await chromium.launch({ channel });
const report = {
  status: "running",
  revision: execFileSync("git", ["rev-parse", "HEAD"], { encoding: "utf8" }).trim(),
  browser: browser.version(),
  channel,
  platform: platform(),
  release: release(),
  cpu: cpus()[0].model,
  logicalProcessors: cpus().length,
  frames,
  warmup,
  rounds,
  sources,
  samples: [],
  scope:
    "Browser WebGL experiment; no cartridge VM, game simulation, native player or dynamic lighting. Other desktop GPU activity is uncontrolled.",
};
try {
  const cdp = await browser.newBrowserCDPSession();
  const info = await cdp.send("SystemInfo.getInfo");
  report.devices = info.gpu.devices;
  report.features = info.gpu.featureStatus;
  const page = await browser.newPage({
    viewport: { width: 1920, height: 1440 },
    deviceScaleFactor: 1,
  });
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  // Keep the real renderer, but stop the viewer's competing animation/UI loop.
  // The benchmark uses the original rAF to measure normal browser scheduling.
  await page.addInitScript(() => {
    window.benchmarkFrame = window.requestAnimationFrame.bind(window);
    window.requestAnimationFrame = () => 0;
  });
  await page.goto(`http://127.0.0.1:${server.address().port}/index.html`);
  await page.waitForFunction(() => window.riverDemo?.ready || window.riverDemo?.error, undefined, {
    polling: 100,
  });
  assert.equal(await page.evaluate(() => window.riverDemo.error), "");
  report.graphics = await page.evaluate(() => {
    document.querySelector("header").style.display = "none";
    document.querySelector("section").style.display = "none";
    const gl = window.riverDemo.renderer.gl;
    const debug = gl.getExtension("WEBGL_debug_renderer_info");
    return {
      renderer: debug
        ? gl.getParameter(debug.UNMASKED_RENDERER_WEBGL)
        : gl.getParameter(gl.RENDERER),
      vendor: debug ? gl.getParameter(debug.UNMASKED_VENDOR_WEBGL) : gl.getParameter(gl.VENDOR),
      timer: Boolean(gl.getExtension("EXT_disjoint_timer_query_webgl2")),
      worldVertices: window.riverDemo.renderer.metadata.worldVertices,
      rabbitVertices: window.riverDemo.renderer.metadata.rabbitVertices,
    };
  });
  const cases = [];
  for (const width of [320, 640]) {
    for (const motion of ["pan", "orbit"]) {
      for (const supersampling of [false, true]) {
        cases.push({
          width,
          motion,
          supersampling,
          stabilization: "snapped",
          smoothPresentation: true,
        });
      }
    }
    cases.push({
      width,
      motion: "orbit",
      supersampling: true,
      stabilization: "scene-surface",
      smoothPresentation: true,
    });
    cases.push({
      width,
      motion: "orbit",
      supersampling: true,
      stabilization: "snapped",
      smoothPresentation: false,
    });
  }
  for (let round = 0; round < rounds; round++) {
    // Reverse order on alternating rounds to expose ordering/warmup effects.
    const order = round % 2 ? cases.toReversed() : cases;
    for (const configuration of order) {
      const result = await page.evaluate(
        async ({ configuration, frames, warmup }) => {
          const { viewBasis } = await import("./river-live.js");
          const renderer = window.riverDemo.renderer;
          const gl = renderer.gl;
          const timer = gl.getExtension("EXT_disjoint_timer_query_webgl2");
          const state = {
            ...window.riverDemo,
            ...configuration,
            presentationWidth: 1920,
            yaw: 0,
            angle: 0,
          };
          const origin = [...state.target];
          const basis = viewBasis(renderer.metadata.camera.forward);
          const cpu = [],
            intervals = [],
            completed = [],
            pending = [];
          let disjoint = false;
          let lastTime;
          let activeScene;
          let activePost;
          const nextFrame = () => new Promise((done) => window.benchmarkFrame(done));
          const move = (step) => {
            const phase = step / frames;
            state.yaw = configuration.motion === "orbit" ? (phase * Math.PI) / 2 : 0;
            state.target = origin.map(
              (v, i) => v + basis.right[i] * Math.sin(phase * Math.PI * 2) * 3,
            );
          };
          const originalResolve = renderer.resolve;
          // Timer queries may not nest. End the scene query before starting resolve
          // and presentation; paired results provide the frame's total GPU work.
          renderer.resolve = function (...args) {
            if (activeScene) {
              gl.endQuery(timer.TIME_ELAPSED_EXT);
              activePost = gl.createQuery();
              gl.beginQuery(timer.TIME_ELAPSED_EXT, activePost);
            }
            originalResolve.apply(this, args);
            if (activePost) {
              gl.endQuery(timer.TIME_ELAPSED_EXT);
            }
          };
          const harvest = () => {
            if (!timer) {
              return;
            }
            disjoint ||= Boolean(gl.getParameter(timer.GPU_DISJOINT_EXT));
            while (
              pending.length &&
              gl.getQueryParameter(pending[0].post, gl.QUERY_RESULT_AVAILABLE)
            ) {
              const pair = pending.shift();
              const scene = gl.getQueryParameter(pair.scene, gl.QUERY_RESULT) / 1e6;
              const post = gl.getQueryParameter(pair.post, gl.QUERY_RESULT) / 1e6;
              completed.push({ scene, post, total: scene + post });
              gl.deleteQuery(pair.scene);
              gl.deleteQuery(pair.post);
            }
          };
          try {
            // Allocate all targets/clouds and warm the shader paths before timing.
            renderer.render(state);
            for (let i = 0; i < warmup; i++) {
              await nextFrame();
              move(i);
              renderer.render(state);
            }
            gl.finish();
            for (let i = 0; i < frames; i++) {
              const time = await nextFrame();
              if (lastTime !== undefined) {
                intervals.push(time - lastTime);
              }
              lastTime = time;
              harvest();
              activeScene = timer ? gl.createQuery() : null;
              activePost = null;
              if (timer) {
                gl.beginQuery(timer.TIME_ELAPSED_EXT, activeScene);
              }
              const start = performance.now();
              move(i);
              renderer.render(state);
              cpu.push(performance.now() - start);
              if (timer) {
                pending.push({ scene: activeScene, post: activePost });
              }
              activeScene = null;
              activePost = null;
            }
            for (let i = 0; pending.length && i < 180; i++) {
              await nextFrame();
              harvest();
            }
            // Readback forces a GPU-to-CPU result instead of trusting finish()
            // alone as a browser round-trip. This is a separate diagnostic: the
            // shipping render path should not read pixels back every frame.
            const synchronized = [];
            const pixel = new Uint8Array(4);
            for (let i = 0; i < 30; i++) {
              await nextFrame();
              move(i);
              const start = performance.now();
              renderer.render(state);
              gl.finish();
              gl.readPixels(0, 0, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, pixel);
              synchronized.push(performance.now() - start);
            }
            const summarize = (values) => {
              if (!values.length) {
                return null;
              }
              const sorted = values.toSorted((a, b) => a - b);
              const at = (q) =>
                sorted[Math.min(sorted.length - 1, Math.ceil(q * sorted.length) - 1)];
              return {
                count: values.length,
                median: at(0.5),
                p95: at(0.95),
                p99: at(0.99),
                max: sorted.at(-1),
              };
            };
            return {
              cpu: summarize(cpu),
              frameInterval: summarize(intervals),
              intervalsAbove18ms: intervals.filter((v) => v > 18).length,
              gpu:
                timer && !disjoint && !pending.length
                  ? {
                      scene: summarize(completed.map((v) => v.scene)),
                      post: summarize(completed.map((v) => v.post)),
                      total: summarize(completed.map((v) => v.total)),
                    }
                  : null,
              disjoint,
              pendingQueries: pending.length,
              synchronized: summarize(synchronized),
              readbackAlpha: pixel[3],
              internal: [renderer.internalWidth, renderer.internalHeight],
              presentation: [renderer.canvas.width, renderer.canvas.height],
              error: gl.getError(),
              hidden: document.hidden,
            };
          } finally {
            renderer.resolve = originalResolve;
            for (const pair of pending) {
              gl.deleteQuery(pair.scene);
              gl.deleteQuery(pair.post);
            }
          }
        },
        { configuration, frames, warmup },
      );
      assert.equal(result.error, 0);
      assert.equal(result.hidden, false);
      assert.equal(result.readbackAlpha, 255);
      report.samples.push({ round, ...configuration, ...result });
      await writeFile(resolve(root, "performance.json"), JSON.stringify(report, null, 2));
      console.log(
        JSON.stringify({
          round,
          ...configuration,
          cpuP95: result.cpu.p95,
          gpuP95: result.gpu?.total?.p95,
          frameP95: result.frameInterval.p95,
        }),
      );
    }
  }
  assert.deepEqual(errors, []);
  report.status = "passed";
} finally {
  await browser.close();
  await new Promise((done) => server.close(done));
  await writeFile(resolve(root, "performance.json"), JSON.stringify(report, null, 2));
}
console.log(`Performance report: ${resolve(root, "performance.json")}`);

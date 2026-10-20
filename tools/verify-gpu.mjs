import assert from "node:assert/strict";
import { once } from "node:events";
import { mkdir, copyFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { chromium } from "playwright";
import { serve } from "./serve.mjs";
import { tool, run } from "./toolchain.mjs";

const root = resolve("build/gpu-validation");
await mkdir(root, { recursive: true });
run(tool("odin"), ["test", "tests/3d", "-o:none", `-out:${root}/resources.exe`]);
run(tool("odin"), ["build", "tests/gpu/native", "-o:none", `-out:${root}/device.exe`]);
await copyFile("build/odin-player/native/SDL3.dll", resolve(root, "SDL3.dll"));
const report = {
  status: "running",
  nativeFixture: JSON.parse(run(resolve(root, "device.exe"), [])),
  cases: [],
};
assert.equal(report.nativeFixture.pixel, 0xff0000ff);
assert.equal(report.nativeFixture.depth, 0.25);
const server = serve(".", 0);
await once(server, "listening");
const browser = await chromium.launch({ channel: process.env.PLAYER_BROWSER_CHANNEL || "chrome" });
try {
  for (const language of ["odin", "luau"]) {
    for (const ssaa of ["off", "2x", "1080p"]) {
      const page = await browser.newPage();
      const base = `/build/compact-3d/${language}/build/web`;
      await page.goto(
        `http://127.0.0.1:${server.address().port}${base}/player.html?renderer=gpu&ssaa=${ssaa}&pixel-snap&smoke`,
      );
      await page.waitForFunction(() => window.playerStatus?.ready || window.playerStatus?.error);
      await page.locator("#start").click();
      await page.waitForFunction(
        () => window.playerStatus.ticks >= 120 || window.playerStatus.error,
      );
      const status = await page.evaluate(() => window.playerStatus);
      assert.equal(status.error, "");
      assert.equal(status.graphics.effective, "gpu");
      const native = JSON.parse(
        run(resolve(`build/compact-3d/${language}/build/native/player.exe`), [
          "--check",
          "--renderer",
          "gpu",
          "--ssaa",
          ssaa,
          "--pixel-snap",
        ]),
      );
      assert.equal(status.hash, native.hash, `${language}/${ssaa}: native/browser GPU parity`);
      report.cases.push({
        language,
        ssaa,
        hash: status.hash,
        width: status.width,
        height: status.height,
      });
      await page.close();
    }
    const page = await browser.newPage({ viewport: { width: 1920, height: 1400 } });
    const base = `/build/compact-3d/${language}/build/web`;
    await page.goto(
      `http://127.0.0.1:${server.address().port}${base}/player.html?renderer=gpu&ssaa=1080p&smooth-pan`,
    );
    await page.waitForFunction(() => window.playerStatus?.ready || window.playerStatus?.error);
    assert.equal(await page.evaluate(() => window.playerStatus.error), "");
    assert(await page.evaluate(() => window.playerStatus.smoothPresentation));
    assert(
      await page.evaluate(
        () => document.querySelector("#canvas").width > window.playerStatus.width,
      ),
    );
    const frames = await page.evaluate(
      async ({ base, language }) => {
        const worker = new Worker(base + "/worker.js", { type: "module" });
        const request = (message, type) =>
          new Promise((resolve, reject) => {
            const timeout = setTimeout(() => reject(new Error("GPU worker timeout")), 10000);
            worker.onerror = (event) => {
              clearTimeout(timeout);
              reject(new Error(event.message));
            };
            worker.onmessage = ({ data }) => {
              if (data.type === "error") {
                clearTimeout(timeout);
                reject(new Error(data.error));
              } else if (data.type === type) {
                clearTimeout(timeout);
                resolve(data);
              }
            };
            worker.postMessage(message);
          });
        try {
          await request(
            {
              type: "load",
              gameUrl: location.origin + base + (language === "odin" ? "/game.wasm" : "/game.luau"),
              graphics: { backend: "gpu", ssaa: "1080p", smoothPan: true },
              presentationSize: [1920, 1080],
            },
            "ready",
          );
          const high = await request(
            { type: "step", steps: 1, input: { buttons: 16, pointer: false, x: 0, y: 0 } },
            "frame",
          );
          const perspective = await request(
            { type: "step", steps: 1, input: { buttons: 2, pointer: false, x: 0, y: 0 } },
            "frame",
          );
          return {
            high: {
              hash: high.hash,
              width: high.width,
              presentationWidth: high.presentationWidth,
              smooth: high.smoothPresentation,
            },
            perspective: {
              smooth: perspective.smoothPresentation,
              width: perspective.width,
              presentationWidth: perspective.presentationWidth,
            },
          };
        } finally {
          worker.terminate();
        }
      },
      { base, language },
    );
    assert.equal(frames.high.width, 640);
    assert.equal(frames.high.presentationWidth, 1920);
    assert(frames.high.smooth);
    assert.equal(frames.perspective.smooth, false);
    assert.equal(frames.perspective.presentationWidth, 320);
    const inputs = resolve(root, "action.inputs");
    await writeFile(inputs, "16\n");
    const nativeHigh = JSON.parse(
      run(resolve(`build/compact-3d/${language}/build/native/player.exe`), [
        "--replay",
        inputs,
        "--renderer",
        "gpu",
        "--ssaa",
        "1080p",
        "--smooth-pan",
      ]),
    );
    assert.equal(nativeHigh.hash, frames.high.hash);
    report.cases.push({ language, smooth: frames });
    await page.locator("#graphics-backend").selectOption("cpu");
    await page.locator("#graphics-apply").click();
    await page.waitForFunction(
      () =>
        (window.playerStatus.ready && window.playerStatus.graphics?.effective === "cpu") ||
        window.playerStatus.error,
    );
    assert.equal(await page.evaluate(() => window.playerStatus.error), "");
    assert.equal(await page.evaluate(() => window.playerStatus.graphics.requested.ssaa), "off");
    await page.close();
  }
  const page = await browser.newPage();
  await page.goto(`http://127.0.0.1:${server.address().port}/build/odin-player/web/player.html`);
  await page.waitForFunction(() => window.playerStatus?.ready);
  report.browserFixtures = await page.evaluate(async () => {
    const { createGpu, normalizeGraphics } = await import("./gpu.js");
    const rows = [];
    for (const ssaa of ["off", "2x", "1080p"]) {
      const device = await createGpu(normalizeGraphics({ backend: "gpu", ssaa }));
      const memory = new WebAssembly.Memory({ initial: 1 });
      const vertices = new Float32Array(memory.buffer, 0, 21);
      vertices.set([
        -0.8, -0.8, 0.25, 1, 255, 0, 0, 0, 0.8, 0.25, 1, 255, 0, 0, 0.8, -0.8, 0.25, 1, 255, 0, 0,
      ]);
      const color = 256,
        depth = color + 32 * 32 * 4;
      new Float32Array(memory.buffer, depth, 32 * 32).fill(1);
      const result = device.raster(
        memory,
        0,
        3,
        color,
        depth,
        32,
        32,
        0,
        0,
        32,
        32,
        0xff000000,
        1,
        2,
      );
      const center = (16 * 32 + 16) * 4;
      const rgba = Array.from(new Uint8Array(memory.buffer, color + center, 4));
      const z = new Float32Array(memory.buffer, depth + center, 1)[0];
      const colors = new Uint8Array(memory.buffer, color, 32 * 32 * 4);
      const coverage = colors.filter((v, i) => i % 4 === 3 && v > 0 && v < 255).length;
      rows.push({ ssaa, result, rgba, z, coverage });
      device.gl.getExtension("WEBGL_lose_context")?.loseContext();
    }
    return rows;
  });
  for (const row of report.browserFixtures) {
    assert.equal(row.result, 1);
    assert.deepEqual(row.rgba, [255, 0, 0, 255]);
    assert.equal(row.z, 0.25);
    assert.equal(row.coverage > 0, row.ssaa !== "off");
  }
  await page.close();
  const unavailable = await chromium.launch({
    channel: process.env.PLAYER_BROWSER_CHANNEL || "chrome",
  });
  try {
    const fallbackPage = await unavailable.newPage();
    // Inject device unavailability in the Worker; browser launch switches do
    // not consistently disable OffscreenCanvas WebGL on installed browsers.
    await fallbackPage.route("**/worker.js", async (route) => {
      const response = await route.fetch();
      const body =
        `const originalContext=OffscreenCanvas.prototype.getContext;
OffscreenCanvas.prototype.getContext=function(kind,...args){return kind==="webgl2"?null:originalContext.call(this,kind,...args);};\n` +
        (await response.text());
      await route.fulfill({ response, body });
    });
    const base = `http://127.0.0.1:${server.address().port}/build/odin-player/web/player.html`;
    await fallbackPage.goto(base + "?renderer=auto");
    await fallbackPage.waitForFunction(
      () => window.playerStatus?.ready || window.playerStatus?.error,
    );
    assert.equal(await fallbackPage.evaluate(() => window.playerStatus.graphics?.effective), "cpu");
    await fallbackPage.goto(base + "?renderer=gpu");
    await fallbackPage.waitForFunction(() => window.playerStatus?.error);
    assert.match(await fallbackPage.evaluate(() => window.playerStatus.error), /WebGL 2/);
    await fallbackPage.goto(base + "?renderer=invalid");
    await fallbackPage.waitForFunction(() => window.playerStatus?.error);
    assert.match(await fallbackPage.evaluate(() => window.playerStatus.error), /Invalid graphics/);
  } finally {
    await unavailable.close();
  }
  const player = resolve("build/odin-player/native/player.exe");
  const automatic = JSON.parse(
    run(player, ["--check", "--renderer", "auto"], {
      env: { ...process.env, SDL_VIDEODRIVER: "dummy" },
    }),
  );
  const reference = JSON.parse(run(player, ["--check", "--renderer", "cpu"]));
  assert.equal(automatic.hash, reference.hash);
  report.fallbacks = {
    browser: "injected unavailable WebGL2 context",
    native: "SDL dummy video driver",
  };
  report.status = "passed";
} finally {
  await browser.close();
  await new Promise((done) => server.close(done));
  await writeFile(resolve(root, "report.json"), JSON.stringify(report, null, 2));
}
console.log(JSON.stringify(report));

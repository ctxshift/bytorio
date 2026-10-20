import assert from "node:assert/strict";
import { once } from "node:events";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { chromium } from "playwright";
import { serve } from "../../tools/serve.mjs";

const root = resolve("build/compact-3d/resolution/river");
await mkdir(root, { recursive: true });
const server = serve(root, 0);
await once(server, "listening");
const browser = await chromium.launch({ channel: process.env.PLAYER_BROWSER_CHANNEL || undefined });
const report = { status: "running", modes: [], controls: {}, filtering: [] };
try {
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto(`http://127.0.0.1:${server.address().port}/index.html`);
  await page.waitForFunction(() => window.riverDemo?.ready || window.riverDemo?.error);
  assert.equal(await page.evaluate(() => window.riverDemo.error), "");
  await page.locator("#pause").check();
  await page.locator("#native").check();
  const waitFrames = async (count = 2) => {
    const frame = await page.evaluate(() => window.riverDemo.frame);
    await page.waitForFunction(
      (limit) => window.riverDemo.frame >= limit || window.riverDemo.error,
      frame + count,
    );
    assert.equal(await page.evaluate(() => window.riverDemo.error), "");
  };
  for (const width of [320, 640, 1920]) {
    await page.locator(`[data-width="${width}"]`).click();
    const pixels = [];
    for (const supersampling of width === 1920 ? [false] : [false, true]) {
      if (width !== 1920) {
        await page.locator("#supersampling").setChecked(supersampling);
      }
      await waitFrames();
      const check = await page.evaluate(() => {
        const s = window.riverDemo;
        const { source, output } = s.renderer.capture();
        const width = s.width;
        const factor = s.internalWidth / width;
        const height = (width * 9) / 16;
        const encode = (v) =>
          Math.round(255 * (v <= 0.0031308 ? v * 12.92 : 1.055 * v ** (1 / 2.4) - 0.055));
        let maximumError = 0;
        let emptyPixels = 0;
        let hash = 2166136261;
        for (let i = 0; i < output.length; i += 4) {
          if (output[i] + output[i + 1] + output[i + 2] === 0 || output[i + 3] !== 255) {
            emptyPixels++;
          }
          hash = Math.imul(hash ^ output[i], 16777619) >>> 0;
          hash = Math.imul(hash ^ output[i + 1], 16777619) >>> 0;
          hash = Math.imul(hash ^ output[i + 2], 16777619) >>> 0;
        }
        for (let y = 3; y < height; y += 17) {
          for (let x = 5; x < width; x += 19) {
            for (let channel = 0; channel < 3; channel++) {
              let sum = 0;
              for (let dy = 0; dy < factor; dy++) {
                for (let dx = 0; dx < factor; dx++) {
                  sum +=
                    source[((y * factor + dy) * s.internalWidth + x * factor + dx) * 4 + channel];
                }
              }
              const expected = encode(sum / (255 * factor * factor));
              maximumError = Math.max(
                maximumError,
                Math.abs(expected - output[(y * width + x) * 4 + channel]),
              );
            }
          }
        }
        const canvas = document.querySelector("#scene");
        return {
          width,
          height,
          internalWidth: s.internalWidth,
          factor,
          emptyPixels,
          maximumError,
          hash,
          canvas: [canvas.width, canvas.height],
          displayed: [canvas.getBoundingClientRect().width, canvas.getBoundingClientRect().height],
          rabbit: s.rabbit,
          target: s.target,
          hardwareAA: s.renderer.gl.getContextAttributes().antialias,
          glError: s.renderer.gl.getError(),
        };
      });
      assert.deepEqual(check.canvas, [width, (width * 9) / 16]);
      assert.deepEqual(check.displayed, check.canvas);
      assert.equal(check.internalWidth, supersampling ? 1920 : width);
      assert.equal(
        check.maximumError <= 1,
        true,
        "GPU output must match independent linear-light averaging",
      );
      assert.equal(check.emptyPixels, 0, "Camera must not reveal a mesh boundary");
      assert.equal(check.hardwareAA, false);
      assert.equal(check.glError, 0);
      if (pixels.length) {
        assert.deepEqual(check.rabbit, pixels[0].rabbit);
        assert.deepEqual(check.target, pixels[0].target);
        assert.notEqual(check.hash, pixels[0].hash, "Filtering must visibly change edge pixels");
      }
      pixels.push(check);
      report.modes.push({ supersampling, ...check });
      await page.locator("#scene").screenshot({
        path: resolve(root, `live-${width}-${supersampling ? "ssaa" : "direct"}.png`),
      });
    }
  }
  assert.equal(await page.locator("#supersampling").isDisabled(), true);
  await page.locator('[data-width="320"]').click();
  await page.locator("#supersampling").uncheck();
  await page.locator("#pause").uncheck();
  await page.locator("#scene").focus();
  const start = await page.evaluate(() => [...window.riverDemo.rabbit]);
  await page.keyboard.down("d");
  await page.waitForFunction((x) => window.riverDemo.rabbit[0] > x + 1.5, start[0]);
  await page.keyboard.up("d");
  const moved = await page.evaluate(() => [...window.riverDemo.rabbit]);
  assert(moved[0] > start[0] + 1.5);
  await page.keyboard.down("d");
  await page.locator("#pause").focus();
  const blurred = await page.evaluate(() => [...window.riverDemo.rabbit]);
  await waitFrames(4);
  assert.deepEqual(
    await page.evaluate(() => window.riverDemo.rabbit),
    blurred,
    "Blur must release held movement keys",
  );
  await page.keyboard.up("d");
  await page.locator("#scene").focus();
  const oldTarget = await page.evaluate(() => [...window.riverDemo.target]);
  await page.keyboard.down("ArrowRight");
  await page.waitForFunction((x) => window.riverDemo.target[0] > x + 0.4, oldTarget[0]);
  await page.keyboard.up("ArrowRight");
  await page.locator("#camera-motion").check();
  const camera = await page.evaluate(() => [...window.riverDemo.target]);
  await page.waitForFunction((old) => Math.abs(window.riverDemo.target[0] - old[0]) > 0.1, camera);
  await page.locator("#pause").check();
  await waitFrames();
  const paused = await page.evaluate(() => ({
    rabbit: [...window.riverDemo.rabbit],
    target: [...window.riverDemo.target],
  }));
  await page.locator("#supersampling").check();
  await waitFrames(3);
  assert.deepEqual(
    await page.evaluate(() => ({
      rabbit: window.riverDemo.rabbit,
      target: window.riverDemo.target,
    })),
    paused,
  );
  await page.locator("#reset").click();
  await waitFrames();
  assert.deepEqual(await page.evaluate(() => window.riverDemo.rabbit), [-4, 8, 19]);
  report.controls = {
    wasd: true,
    blurRelease: true,
    manualPan: true,
    cameraMotion: true,
    pausedComparison: true,
    reset: true,
  };
  // Independent black/white fixture: averaging encoded colors would produce 128,
  // while correct linear-light averaging of an even mix produces approximately 188.
  report.filtering = await page.evaluate(async () => {
    const { RiverRenderer } = await import("./river-live.js");
    const canvas = document.createElement("canvas");
    const fixture = new RiverRenderer(
      canvas,
      { camera: { forward: [0, -0.6, -0.8], viewWidth: 180 }, worldVertices: 0, rabbitVertices: 0 },
      new ArrayBuffer(0),
      new ArrayBuffer(0),
    );
    const gl = fixture.gl;
    const pattern = new Uint8Array(1920 * 1080 * 4);
    for (let y = 0; y < 1080; y++) {
      for (let x = 0; x < 1920; x++) {
        const at = (y * 1920 + x) * 4;
        const value = (x + y) % 2 ? 255 : 0;
        pattern.set([value, value, value, 255], at);
      }
    }
    const checks = [];
    for (const factor of [3, 6]) {
      const width = 1920 / factor;
      fixture.render({
        width,
        supersampling: true,
        rabbit: [0, 0, 0],
        target: [0, 0, 0],
        angle: 0,
      });
      gl.bindTexture(gl.TEXTURE_2D, fixture.texture);
      gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, 1920, 1080, gl.RGBA, gl.UNSIGNED_BYTE, pattern);
      fixture.resolve(width, (width * 9) / 16, factor);
      const { output } = fixture.capture();
      let white = 0;
      for (let y = 0; y < factor; y++) {
        for (let x = 0; x < factor; x++) {
          white += (x + y) % 2;
        }
      }
      const average = white / (factor * factor);
      const expected = Math.round(255 * (1.055 * average ** (1 / 2.4) - 0.055));
      checks.push({ factor, expected, observed: output[0], error: Math.abs(expected - output[0]) });
    }
    gl.getExtension("WEBGL_lose_context")?.loseContext();
    return checks;
  });
  assert(report.filtering.every((check) => check.error <= 1));
  assert.equal(report.filtering.find((check) => check.factor === 6).expected, 188);
  assert.deepEqual(errors, []);
  const metadata = JSON.parse(await readFile(resolve(root, "live-scene.json")));
  assert(metadata.worldVertices > 0 && metadata.rabbitVertices > 0);
  const heightAt = (x, z) =>
    metadata.walk.heights[
      (z - metadata.walk.minZ) * (metadata.walk.maxX - metadata.walk.minX + 1) +
        x -
        metadata.walk.minX
    ];
  assert.equal(heightAt(27, 40), -1, "The open stream must block walking");
  assert.equal(heightAt(-40, -25), -1, "The cottage must block walking");
  assert.equal(heightAt(28, 18), 14, "Bridge deck must provide a raised walkable surface");
  report.status = "passed";
} finally {
  await browser.close();
  await new Promise((done) => server.close(done));
  await writeFile(resolve(root, "live-checks.json"), JSON.stringify(report, null, 2));
}
console.log(
  JSON.stringify({
    status: report.status,
    modes: report.modes.length,
    controls: report.controls,
    filtering: report.filtering,
  }),
);

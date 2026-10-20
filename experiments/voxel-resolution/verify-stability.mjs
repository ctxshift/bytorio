import assert from "node:assert/strict";
import { once } from "node:events";
import { writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { chromium } from "playwright";
import { serve } from "../../tools/serve.mjs";

const root = resolve("build/compact-3d/resolution/river");
const server = serve(root, 0);
await once(server, "listening");
const browser = await chromium.launch({ channel: process.env.PLAYER_BROWSER_CHANNEL || undefined });
const report = { status: "running", modes: [] };
try {
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto(`http://127.0.0.1:${server.address().port}/index.html`);
  await page.waitForFunction(() => window.riverDemo?.ready || window.riverDemo?.error);
  assert.equal(await page.evaluate(() => window.riverDemo.error), "");
  await page.locator("#pause").check();
  await page.locator("#native").check();
  const waitFrames = async () => {
    const frame = await page.evaluate(() => window.riverDemo.frame);
    await page.waitForFunction(
      (before) => window.riverDemo.frame > before + 1 || window.riverDemo.error,
      frame,
    );
    assert.equal(await page.evaluate(() => window.riverDemo.error), "");
  };
  for (const width of [320, 640, 1920]) {
    await page.locator(`[data-width="${width}"]`).click();
    for (const mode of ["snapped", "sprite"]) {
      await page.locator("#stabilization").selectOption(mode);
      for (const ssaa of width === 1920 ? [false] : [false, true]) {
        if (width !== 1920) {
          await page.locator("#supersampling").setChecked(ssaa);
        }
        await waitFrames();
        const check = await page.evaluate(() => {
          const s = window.riverDemo;
          const output = s.renderer.capture().output;
          let empty = 0;
          for (let i = 0; i < output.length; i += 4) {
            if (output[i] + output[i + 1] + output[i + 2] === 0 || output[i + 3] !== 255) {
              empty++;
            }
          }
          return {
            mode: s.stabilization,
            width: s.width,
            internalWidth: s.internalWidth,
            empty,
            rabbit: [...s.rabbit],
            target: [...s.target],
            yaw: s.yaw,
            glError: s.renderer.gl.getError(),
          };
        });
        assert.equal(check.empty, 0);
        assert.equal(check.glError, 0);
        assert.equal(check.internalWidth, ssaa ? 1920 : width);
        assert.deepEqual(
          check.rabbit,
          [-4, 8, 19],
          "Mode switches must preserve simulation position",
        );
        assert.deepEqual(check.target, [0, 24, 0]);
        report.modes.push({ ssaa, ...check });
      }
      if (width === 640) {
        await page.locator("#scene").screenshot({ path: resolve(root, `stable-${mode}-640.png`) });
      }
    }
  }
  report.stability = await page.evaluate(async () => {
    const { viewBasis } = await import("./river-live.js");
    const s = window.riverDemo;
    const r = s.renderer;
    const basis = viewBasis(r.metadata.camera.forward, 0);
    const dot = (a, b) => a.reduce((sum, v, i) => sum + v * b[i], 0);
    const pixel = r.metadata.camera.viewWidth / 640;
    const state = { ...s, width: 640, supersampling: false, stabilization: "snapped", yaw: 0 };
    r.render(state);
    const base = { ...state, target: [...r.renderPose.target], rabbit: [...r.renderPose.rabbit] };
    r.render(base);
    const before = r.capture().output;
    r.render({ ...base, target: base.target.map((v, i) => v + basis.right[i] * pixel * 0.2) });
    const after = r.capture().output;
    const subpixelCameraIdentical = before.every((v, i) => v === after[i]);
    const gridErrors = [r.renderPose.target, r.renderPose.rabbit].flatMap((p) =>
      [basis.right, basis.up].map((axis) => {
        const coordinate = dot(p, axis) / pixel;
        return Math.abs(coordinate - Math.round(coordinate));
      }),
    );
    const spriteState = { ...base, stabilization: "sprite" };
    r.render(spriteState);
    const captures = r.sprite.captures;
    const first = r.sprite.capture();
    r.render({
      ...spriteState,
      rabbit: spriteState.rabbit.map((v, i) => v + basis.right[i] * pixel * 2),
    });
    const second = r.sprite.capture();
    const spriteTranslationIdentical = first.every((v, i) => v === second[i]);
    const translationReusesCapture = r.sprite.captures === captures;
    const partialCoverage = first.filter((v, i) => i % 4 === 3 && v > 0 && v < 255).length;
    const withRabbit = r.capture().output;
    r.resolve(640, 360, 1);
    const withoutRabbit = r.capture().output;
    const compositeChanges = withRabbit.reduce(
      (sum, v, i) => sum + Number(v !== withoutRabbit[i]),
      0,
    );
    r.render({ ...spriteState, angle: spriteState.angle + 0.25 });
    const facingRecaptures = r.sprite.captures === captures + 1;
    r.render({ ...spriteState, yaw: 0.3 });
    const viewRecaptures = r.sprite.captures === captures + 2;
    let orbitEmpty = 0;
    for (const yaw of [0, Math.PI / 2, Math.PI, Math.PI * 1.5]) {
      r.render({ ...spriteState, width: 320, yaw });
      const pixels = r.capture().output;
      for (let i = 0; i < pixels.length; i += 4) {
        orbitEmpty += Number(pixels[i] + pixels[i + 1] + pixels[i + 2] === 0);
      }
    }
    return {
      subpixelCameraIdentical,
      maximumGridError: Math.max(...gridErrors),
      spriteTranslationIdentical,
      translationReusesCapture,
      partialCoverage,
      compositeChanges,
      facingRecaptures,
      viewRecaptures,
      orbitEmpty,
      glError: r.gl.getError(),
    };
  });
  const stability = report.stability;
  assert(stability.subpixelCameraIdentical);
  assert(stability.maximumGridError < 1e-6);
  assert(stability.spriteTranslationIdentical && stability.translationReusesCapture);
  assert(stability.partialCoverage > 0 && stability.compositeChanges > 20);
  assert(stability.facingRecaptures && stability.viewRecaptures);
  assert.equal(stability.orbitEmpty, 0);
  assert.equal(stability.glError, 0);
  report.depthOcclusion = await page.evaluate(async () => {
    const { RiverRenderer } = await import("./river-live.js");
    const quad = (z, color) => {
      const bytes = new ArrayBuffer(6 * 16);
      const view = new DataView(bytes);
      const positions = [
        [-4, 0],
        [4, 0],
        [4, 8],
        [-4, 0],
        [4, 8],
        [-4, 8],
      ];
      positions.forEach(([x, y], i) => {
        view.setFloat32(i * 16, x, true);
        view.setFloat32(i * 16 + 4, y, true);
        view.setFloat32(i * 16 + 8, z, true);
        color.forEach((v, channel) => view.setUint8(i * 16 + 12 + channel, v));
      });
      return bytes;
    };
    const result = [];
    for (const z of [1, -1]) {
      const canvas = document.createElement("canvas");
      const renderer = new RiverRenderer(
        canvas,
        { camera: { forward: [0, 0, -1], viewWidth: 180 }, worldVertices: 6, rabbitVertices: 6 },
        quad(z, [255, 0, 0, 255]),
        quad(0, [0, 255, 0, 255]),
      );
      renderer.render({
        width: 320,
        supersampling: false,
        stabilization: "sprite",
        angle: 0,
        yaw: 0,
        target: [0, 0, 0],
        rabbit: [0, 0, 0],
      });
      const pixels = renderer.capture().output;
      result.push({
        z,
        rgb: Array.from(pixels.slice((97 * 320 + 160) * 4, (97 * 320 + 160) * 4 + 3)),
        error: renderer.gl.getError(),
      });
      renderer.gl.getExtension("WEBGL_lose_context")?.loseContext();
    }
    return result;
  });
  assert.deepEqual(
    report.depthOcclusion.map((row) => row.rgb),
    [
      [255, 0, 0],
      [0, 255, 0],
    ],
  );
  assert(report.depthOcclusion.every((row) => row.error === 0));
  await page.locator('[data-width="320"]').click();
  await page.locator("#pause").uncheck();
  await page.locator("#scene").focus();
  await page.keyboard.down("e");
  await page.waitForFunction(() => window.riverDemo.yaw > 0.05);
  await page.keyboard.up("e");
  await page.locator("#pause").check();
  await waitFrames();
  const yaw = await page.evaluate(() => window.riverDemo.yaw);
  await waitFrames();
  assert.equal(await page.evaluate(() => window.riverDemo.yaw), yaw);
  assert.deepEqual(errors, []);
  report.orbitControl = true;
  report.status = "passed";
} finally {
  await browser.close();
  await new Promise((done) => server.close(done));
  await writeFile(resolve(root, "stability-checks.json"), JSON.stringify(report, null, 2));
}
console.log(JSON.stringify(report));

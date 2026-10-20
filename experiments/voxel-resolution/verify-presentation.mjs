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
const report = { status: "running", presentation: [], surface: [] };
try {
  const page = await browser.newPage({ viewport: { width: 1280, height: 1000 } });
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto(`http://127.0.0.1:${server.address().port}/index.html`);
  await page.waitForFunction(() => window.riverDemo?.ready || window.riverDemo?.error);
  assert.equal(await page.evaluate(() => window.riverDemo.error), "");
  await page.locator("#pause").check();
  assert(await page.evaluate(() => !window.riverDemo.renderer.worldSurface));
  report.presentation = await page.evaluate(async () => {
    const { viewBasis, snapToViewGrid } = await import("./river-live.js");
    const s = window.riverDemo;
    const r = s.renderer;
    const basis = viewBasis(r.metadata.camera.forward);
    const rows = [];
    for (const width of [320, 640]) {
      const pixel = r.metadata.camera.viewWidth / width;
      const target = snapToViewGrid(s.target, basis, pixel);
      for (const mode of ["snapped", "sprite", "surface", "scene-surface"]) {
        for (const ssaa of [false, true]) {
          const state = {
            ...s,
            width,
            yaw: 0,
            stabilization: mode,
            supersampling: ssaa,
            smoothPresentation: true,
            presentationWidth: 1920,
            target,
          };
          r.render(state);
          const scale = r.presentation.scale;
          // The presentation must be exact even when crossing a snap boundary.
          // Re-rasterizing geometry can separately change rare edge/depth samples.
          for (const axis of ["right", "up"]) {
            for (const phase of [0, 0.49]) {
              const at = (fraction) => target.map((v, i) => v + basis[axis][i] * pixel * fraction);
              r.render({ ...state, target: at(phase) });
              const before = r.capture().output;
              r.render({ ...state, target: at(phase + 1 / scale) });
              const after = r.capture().output;
              let differences = 0;
              let maximumError = 0;
              const examples = [];
              const w = r.canvas.width;
              const h = r.canvas.height;
              for (let y = 0; y < h - Number(axis === "up"); y++) {
                for (let x = 0; x < w - Number(axis === "right"); x++) {
                  for (let c = 0; c < 4; c++) {
                    const a = after[(y * w + x) * 4 + c];
                    const b =
                      before[
                        ((y + Number(axis === "up")) * w + x + Number(axis === "right")) * 4 + c
                      ];
                    differences += Number(a !== b);
                    maximumError = Math.max(maximumError, Math.abs(a - b));
                    if (a !== b && examples.length < 5) {
                      examples.push({ x, y, c, a, b });
                    }
                  }
                }
              }
              const empty = after.filter((v, i) => i % 4 === 3 && v !== 255).length;
              const logicalWidth = width + 2;
              const logical = new Uint8Array(logicalWidth * ((width * 9) / 16 + 2) * 4);
              const gl = r.gl;
              gl.bindFramebuffer(gl.FRAMEBUFFER, r.presentationFramebuffer);
              gl.readPixels(
                0,
                0,
                logicalWidth,
                (width * 9) / 16 + 2,
                gl.RGBA,
                gl.UNSIGNED_BYTE,
                logical,
              );
              gl.bindFramebuffer(gl.FRAMEBUFFER, null);
              let presentationErrors = 0;
              for (let y = 0; y < h; y++) {
                const sy = Math.floor((y + 0.5) / scale + 1 + r.presentation.residual[1]);
                for (let x = 0; x < w; x++) {
                  const sx = Math.floor((x + 0.5) / scale + 1 + r.presentation.residual[0]);
                  for (let c = 0; c < 4; c++) {
                    presentationErrors += Number(
                      after[(y * w + x) * 4 + c] !== logical[(sy * logicalWidth + sx) * 4 + c],
                    );
                  }
                }
              }
              rows.push({
                width,
                axis,
                mode,
                ssaa,
                phase,
                scale,
                differences,
                maximumError,
                examples,
                presentationErrors,
                empty,
                error: r.gl.getError(),
              });
            }
          }
        }
      }
    }
    return rows;
  });
  for (const row of report.presentation) {
    assert.equal(row.scale, 1920 / row.width);
    if (row.phase === 0) {
      assert.equal(row.differences, 0, JSON.stringify(row));
    }
    assert.equal(row.presentationErrors, 0, JSON.stringify(row));
    assert.equal(row.empty, 0);
    assert.equal(row.error, 0);
  }
  report.surface = await page.evaluate(() => {
    const s = window.riverDemo;
    const r = s.renderer;
    const samples = r.surface.samples;
    const initial = samples.slice();
    const rows = [];
    for (const mode of ["surface", "scene-surface"]) {
      for (const width of [320, 640, 1920]) {
        for (const ssaa of width === 1920 ? [false] : [false, true]) {
          const state = {
            ...s,
            width,
            supersampling: ssaa,
            stabilization: mode,
            smoothPresentation: false,
            yaw: 0,
            angle: 0,
          };
          r.render(state);
          const first = r.capture().output;
          r.render({ ...state, yaw: 0.55, angle: 0.35 });
          const rotated = r.capture().output;
          r.render(state);
          const returned = r.capture().output;
          rows.push({
            mode,
            width,
            ssaa,
            count: r.surface.count,
            sameBuffer: samples === r.surface.samples,
            unchanged: initial.every((v, i) => v === samples[i]),
            returnIdentical: first.every((v, i) => v === returned[i]),
            rotationChangesImage: first.some((v, i) => v !== rotated[i]),
            error: r.gl.getError(),
          });
        }
      }
    }
    return rows;
  });
  for (const row of report.surface) {
    assert(
      row.count > 0 &&
        row.sameBuffer &&
        row.unchanged &&
        row.returnIdentical &&
        row.rotationChangesImage,
    );
    assert.equal(row.error, 0);
  }
  report.worldSurface = await page.evaluate(() => {
    const s = window.riverDemo;
    const r = s.renderer;
    const cloud = r.worldSurface;
    const samples = cloud.samples;
    const buffer = cloud.buffer;
    const initial = samples.slice();
    const state = {
      ...s,
      width: 320,
      supersampling: false,
      smoothPresentation: false,
      stabilization: "scene-surface",
      yaw: 0,
      angle: 0,
    };
    const views = [];
    for (let step = 0; step < 8; step++) {
      r.render({ ...state, yaw: (step * Math.PI) / 4 });
      const output = r.capture().output;
      let uncovered = 0;
      for (let i = 0; i < output.length; i += 4) {
        uncovered += Number(output[i] + output[i + 1] + output[i + 2] === 0);
      }
      views.push({ yaw: (step * Math.PI) / 4, uncovered, error: r.gl.getError() });
    }
    r.render(state);
    const reference = r.capture().output;
    // Removing the triangle draw count must not affect the sampled world.
    const worldVertices = r.metadata.worldVertices;
    let noTriangles;
    try {
      r.metadata.worldVertices = 0;
      r.render(state);
      noTriangles = r.capture().output;
    } finally {
      r.metadata.worldVertices = worldVertices;
    }
    r.render({ ...state, stabilization: "snapped" });
    const triangles = r.capture().output;
    r.render(state);
    const returned = r.capture().output;
    return {
      views,
      count: cloud.count,
      spacing: cloud.spacing,
      bytes: samples.byteLength,
      unchanged: initial.every((v, i) => v === samples[i]),
      reused:
        r.worldSurface === cloud &&
        r.worldSurface.samples === samples &&
        r.worldSurface.buffer === buffer,
      noTriangleFallback: reference.every((v, i) => v === noTriangles[i]),
      returnIdentical: reference.every((v, i) => v === returned[i]),
      differsFromTriangles: reference.some((v, i) => v !== triangles[i]),
      error: r.gl.getError(),
    };
  });
  const world = report.worldSurface;
  assert(
    world.unchanged &&
      world.reused &&
      world.noTriangleFallback &&
      world.returnIdentical &&
      world.differsFromTriangles,
  );
  assert.equal(world.count, 682064);
  assert.equal(world.spacing, 0.5);
  assert.equal(world.bytes, world.count * 9 * 4);
  assert(world.views.every((view) => view.uncovered === 0 && view.error === 0));
  assert.equal(world.error, 0);
  report.surfaceFixtures = await page.evaluate(async () => {
    const { RiverRenderer } = await import("./river-live.js");
    const { surfaceSamples } = await import("./river-surface.js");
    const quad = (z, color, extent = 4) => {
      const bytes = new ArrayBuffer(96);
      const view = new DataView(bytes);
      const positions = [
        [-extent, 0],
        [extent, 0],
        [extent, extent * 2],
        [-extent, 0],
        [extent, extent * 2],
        [-extent, extent * 2],
      ];
      positions.forEach(([x, y], vertex) => {
        [x, y, z].forEach((v, axis) => view.setFloat32(vertex * 16 + axis * 4, v, true));
        [...color, 255].forEach((v, c) => view.setUint8(vertex * 16 + 12 + c, v));
      });
      return bytes;
    };
    const unit = surfaceSamples(quad(0, [0, 255, 0], 0.5));
    const cells = [];
    for (let i = 0; i < unit.length; i += 9) {
      cells.push(Array.from(unit.slice(i, i + 9)));
    }
    const depth = [];
    for (const [z, yaw] of [
      [1, 0],
      [-1, 0],
      [-1, Math.PI],
    ]) {
      const renderer = new RiverRenderer(
        document.createElement("canvas"),
        { camera: { forward: [0, 0, -1], viewWidth: 180 }, worldVertices: 6, rabbitVertices: 6 },
        quad(z, [255, 0, 0]),
        quad(0, [0, 255, 0]),
      );
      renderer.render({
        width: 320,
        supersampling: false,
        stabilization: "surface",
        angle: 0,
        yaw,
        target: [0, 0, 0],
        rabbit: [0, 0, 0],
      });
      const output = renderer.capture().output;
      depth.push({
        z,
        yaw,
        rgb: Array.from(output.slice((97 * 320 + 160) * 4, (97 * 320 + 160) * 4 + 3)),
        error: renderer.gl.getError(),
      });
      renderer.gl.getExtension("WEBGL_lose_context")?.loseContext();
    }
    return { cells, depth };
  });
  const fixture = report.surfaceFixtures;
  assert.equal(fixture.cells.length, 16);
  assert.equal(new Set(fixture.cells.map((p) => p.slice(0, 3).join(","))).size, 16);
  for (const cell of fixture.cells) {
    assert([-0.375, -0.125, 0.125, 0.375].includes(cell[0]));
    assert([0.125, 0.375, 0.625, 0.875].includes(cell[1]));
    assert.deepEqual(cell.slice(2), [0, 0, 0, 1, 0, 1, 0]);
  }
  assert.deepEqual(
    fixture.depth.map((row) => row.rgb),
    [
      [255, 0, 0],
      [0, 255, 0],
      [255, 0, 0],
    ],
  );
  assert(fixture.depth.every((row) => row.error === 0));
  await page.locator("#stabilization").selectOption("surface");
  await page.locator("#smooth-presentation").check();
  await page.locator("#actual").check();
  await page.setViewportSize({ width: 1920, height: 1500 });
  await page.locator('[data-width="320"]').click();
  await page.waitForFunction(() => window.riverDemo.renderer.presentation?.scale === 6);
  await page.locator("#scene").screenshot({ path: resolve(root, "surface-smooth-320.png") });
  await page.locator("#stabilization").selectOption("scene-surface");
  await page.waitForFunction(() => window.riverDemo.stabilization === "scene-surface");
  await page.locator("#scene").screenshot({ path: resolve(root, "scene-surface-smooth-320.png") });
  await page.locator("#native").check();
  await page.waitForFunction(() => !window.riverDemo.smoothPresentation);
  assert(await page.locator("#smooth-presentation").isDisabled());
  await page.locator("#native").uncheck();
  await page.locator("#stabilization").selectOption("continuous");
  assert(await page.locator("#smooth-presentation").isDisabled());
  assert.deepEqual(errors, []);
  report.status = "passed";
} finally {
  await browser.close();
  await new Promise((done) => server.close(done));
  await writeFile(resolve(root, "presentation-checks.json"), JSON.stringify(report, null, 2));
}
console.log(
  JSON.stringify({
    status: report.status,
    presentationCases: report.presentation.length,
    surfaceCases: report.surface.length,
  }),
);

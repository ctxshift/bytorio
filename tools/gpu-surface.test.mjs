import assert from "node:assert/strict";
import { test } from "node:test";
import { surfacePatches, SURFACE_RECORD_FLOATS } from "../runtime/odin/web/gpu-surface.js";
import { normalizeGraphics } from "../runtime/odin/web/gpu.js";

function rectangle(width = 2, height = 1, axis = 2, reversed = false) {
  const bytes = new ArrayBuffer(4 * 16 + 6 * 4);
  const data = new DataView(bytes);
  const axes = [0, 1, 2].filter((i) => i !== axis);
  for (const [i, p] of [
    [0, [0, 0]],
    [1, [width, 0]],
    [2, [width, height]],
    [3, [0, height]],
  ]) {
    data.setFloat32(i * 16 + axis * 4, 3, true);
    data.setFloat32(i * 16 + axes[0] * 4, p[0] - 2, true);
    data.setFloat32(i * 16 + axes[1] * 4, p[1] - 1, true);
    data.setUint32(i * 16 + 12, 0xff0000ff, true);
  }
  const order = reversed ? [0, 2, 1, 0, 3, 2] : [0, 1, 2, 0, 2, 3];
  order.forEach((value, i) => data.setUint32(64 + i * 4, value, true));
  return data;
}

test("persistent unit patches have independent positions, color and winding", () => {
  const data = rectangle();
  const patches = surfacePatches(data, 4, 6);
  assert.deepEqual(
    [...patches],
    [-2, -1, 3, 1, 0, 0, 1, 0, 0, 0, 1, 0, -1, -1, 3, 1, 0, 0, 1, 0, 0, 0, 1, 0],
  );
  assert.equal(patches.byteLength, 96);
  assert.deepEqual(surfacePatches(data, 4, 6), patches);
  data.setFloat32(0, 100, true);
  assert.equal(patches[0], -2, "resident records own their positions");
  for (const axis of [0, 1, 2]) {
    for (const reversed of [false, true]) {
      const result = surfacePatches(rectangle(2, 1, axis, reversed), 4, 6);
      assert.equal(result.length, 2 * SURFACE_RECORD_FLOATS);
      const a = result.slice(6, 9),
        b = result.slice(9, 12);
      const normal = [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
      ];
      assert.equal(normal[axis], (axis === 1 ? -1 : 1) * (reversed ? -1 : 1));
    }
  }
});

test("sampling rejects unsupported geometry and oversized expansions before allocation", () => {
  assert.throws(() => surfacePatches(rectangle(), 4, 3), /rectangle pairs/);
  const bent = rectangle();
  bent.setFloat32(2 * 16 + 8, 4, true);
  assert.throws(() => surfacePatches(bent, 4, 6), /rectangle pairs/);
  const gradient = rectangle();
  gradient.setUint32(12, 0xff00ff00, true);
  assert.throws(() => surfacePatches(gradient, 4, 6), /rectangle pairs/);
  assert.throws(() => surfacePatches(rectangle(2000, 2000), 4, 6), /bound/);
  assert.throws(() => surfacePatches(rectangle(1.5, 1), 4, 6), /rectangle pairs/);
});

test("palette samples are snapshots and the GPU mode is explicit", () => {
  const data = rectangle();
  for (let i = 0; i < 4; i++) {
    data.setUint32(i * 16 + 12, 1, true);
  }
  const palette = new Uint8Array(1024);
  palette.set([0, 255, 0, 255], 4);
  const patches = surfacePatches(data, 4, 6, palette);
  palette[5] = 0;
  assert.deepEqual([...patches.slice(3, 6)], [0, 1, 0]);
  assert.equal(normalizeGraphics().backend, "cpu");
  assert.equal(normalizeGraphics().surfaceSamples, false);
  assert.throws(() => normalizeGraphics({ surfaceSamples: true }), /GPU renderer/);
  const settings = normalizeGraphics({ backend: "gpu", surfaceSamples: true });
  assert.equal(settings.residentMeshes, true);
  assert.equal(settings.pixelSnap, true);
  assert.equal(settings.surfaceSamples, true);
});

// Experimental sampler for flat, axis-aligned rectangles encoded as triangle
// pairs. Each resident record is one unit patch; four fixed sample identities
// are expanded by the vertex shader, without storing four copies of the patch.
export const SURFACE_RECORD_FLOATS = 12;
export const SURFACE_POINTS_PER_PATCH = 4;
export const SURFACE_CACHE_BYTES = 64 * 1024 * 1024;

export function surfacePatches(data, vertexCount, indexCount, palette = null) {
  const maxPatches = Math.floor(SURFACE_CACHE_BYTES / (SURFACE_RECORD_FLOATS * 4));
  if (indexCount % 6 !== 0 || vertexCount * 16 + indexCount * 4 > data.byteLength) {
    throw new Error("Surface samples require flat axis-aligned rectangle pairs.");
  }
  const paletteView =
    palette && new DataView(palette.buffer, palette.byteOffset, palette.byteLength);
  const rectangles = [];
  let count = 0;
  for (let face = 0; face < indexCount; face += 6) {
    const points = [];
    const colors = [];
    for (let i = 0; i < 6; i++) {
      const index = data.getUint32(vertexCount * 16 + (face + i) * 4, true);
      if (index >= vertexCount) {
        throw new Error("Surface sample vertex index is out of bounds.");
      }
      const at = index * 16;
      points.push([0, 1, 2].map((axis) => data.getFloat32(at + axis * 4, true)));
      const color = data.getUint32(at + 12, true);
      colors.push(paletteView ? paletteView.getUint32(color * 4, true) : color);
    }
    const normal = (at) => {
      const a = points[at + 1].map((v, i) => v - points[at][i]);
      const b = points[at + 2].map((v, i) => v - points[at][i]);
      return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
    };
    const n = normal(0);
    const m = normal(3);
    const axis = [0, 1, 2].find((i) => n[i] !== 0);
    const axes = [0, 1, 2].filter((i) => i !== axis);
    const low = [0, 1, 2].map((i) => Math.min(...points.map((p) => p[i])));
    const high = [0, 1, 2].map((i) => Math.max(...points.map((p) => p[i])));
    const width = high[axes[0]] - low[axes[0]];
    const height = high[axes[1]] - low[axes[1]];
    const cornerMasks = [0, 0];
    points.forEach((p, i) => {
      const corner =
        Number(p[axes[0]] === high[axes[0]]) | (Number(p[axes[1]] === high[axes[1]]) << 1);
      cornerMasks[Math.floor(i / 3)] |= 1 << corner;
    });
    const diagonal = cornerMasks[0] & cornerMasks[1];
    const valid =
      axis !== undefined &&
      low[axis] === high[axis] &&
      n.every((v, i) => Number.isFinite(v) && v === m[i] && (i === axis || v === 0)) &&
      Math.abs(n[axis]) === width * height &&
      Number.isInteger(width) &&
      width > 0 &&
      Number.isInteger(height) &&
      height > 0 &&
      colors.every((v) => v === colors[0]) &&
      points.every((p) => p.every((v, i) => v === low[i] || v === high[i])) &&
      (cornerMasks[0] | cornerMasks[1]) === 15 &&
      (diagonal === 6 || diagonal === 9);
    if (!valid) {
      throw new Error("Surface samples require flat axis-aligned rectangle pairs.");
    }
    count += width * height;
    if (count > maxPatches) {
      throw new Error("Surface sample cache entry exceeds its bound.");
    }
    rectangles.push({
      low,
      axes,
      width,
      height,
      color: colors[0],
      reverse: n[axis] < 0 !== (axis === 1),
    });
  }
  const records = new Float32Array(count * SURFACE_RECORD_FLOATS);
  let cursor = 0;
  for (const { low, axes, width, height, color, reverse } of rectangles) {
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const p = low.slice();
        p[axes[0]] += x;
        p[axes[1]] += y;
        records.set(p, cursor);
        for (let channel = 0; channel < 3; channel++) {
          records[cursor + 3 + channel] = ((color >>> (channel * 8)) & 255) / 255;
        }
        records[cursor + 6 + axes[reverse ? 1 : 0]] = 1;
        records[cursor + 9 + axes[reverse ? 0 : 1]] = 1;
        cursor += SURFACE_RECORD_FLOATS;
      }
    }
  }
  return records;
}

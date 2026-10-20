import assert from "node:assert/strict";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { deflateSync } from "node:zlib";

// Standalone visual experiment: no console profile or renderer changes.
const output = fileURLToPath(new URL("../../build/compact-3d/resolution/", import.meta.url));
const SIZE = 144;
const HEIGHT = 100;
const OFFSET = SIZE / 2;
const cells = new Uint16Array(SIZE * HEIGHT * SIZE);
const palette = [[0, 0, 0]];
const color = (r, g, b) => palette.push([r, g, b]) - 1;
const snow = color(235, 235, 245);
const brown = color(102, 59, 55);
const bark = color(124, 76, 68);
const rust = color(171, 82, 52);
const orange = color(197, 107, 62);
const cream = color(225, 209, 193);
const navy = color(30, 39, 74);
const blue = color(45, 83, 130);
const scarf = color(65, 115, 169);
const coat = color(139, 156, 174);
const seam = color(99, 119, 140);
const skin = color(213, 167, 142);
const dark = color(37, 27, 38);
const green = color(53, 126, 109);
const red = color(157, 60, 74);

function noise(x, y, z) {
  let h = Math.imul(x + 1009, 374761393) ^ Math.imul(y + 917, 668265263);
  h ^= Math.imul(z + 1237, 1274126177);
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return (h ^ (h >>> 16)) >>> 0;
}

function index(x, y, z) {
  return (z * HEIGHT + y) * SIZE + x;
}

function set(x, y, z, value) {
  x = Math.floor(x) + OFFSET;
  y = Math.floor(y);
  z = Math.floor(z) + OFFSET;
  assert(x >= 0 && x < SIZE && y >= 0 && y < HEIGHT && z >= 0 && z < SIZE);
  cells[index(x, y, z)] = value;
}

function box(x, y, z, w, h, d, value) {
  for (let dz = 0; dz < d; dz++) {
    for (let dy = 0; dy < h; dy++) {
      for (let dx = 0; dx < w; dx++) {
        set(x + dx, y + dy, z + dz, value);
      }
    }
  }
}

function ball(cx, cy, cz, rx, ry, rz, value) {
  for (let z = Math.floor(cz - rz); z <= cz + rz; z++) {
    for (let y = Math.floor(cy - ry); y <= cy + ry; y++) {
      for (let x = Math.floor(cx - rx); x <= cx + rx; x++) {
        if (((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 + ((z - cz) / rz) ** 2 <= 1) {
          set(x, y, z, value);
        }
      }
    }
  }
}

function branch(a, b, radius) {
  const length = Math.hypot(...b.map((v, i) => v - a[i]));
  for (let step = 0; step <= Math.ceil(length * 2); step++) {
    const t = step / Math.ceil(length * 2);
    const p = a.map((v, i) => v + (b[i] - v) * t);
    ball(...p, radius, radius, radius, bark);
    if (step % 3 === 0) {
      ball(p[0] - 0.4, p[1] + radius, p[2], radius, 0.8, radius, snow);
    }
  }
}

// Broad drifts and a raised right bank, with a lower winding path between them.
function terrainHeight(x, z) {
  const mound = (cx, cz, rx, rz, height) =>
    height * Math.exp(-(((x - cx) / rx) ** 2 + ((z - cz) / rz) ** 2));
  const frontDrift = mound(-14, 27, 24, 21, 7);
  const rightBank = mound(30, 0, 13, 37, 9);
  const leftDrift = mound(-43, 16, 14, 19, 4);
  const cornerDrift = mound(45, 39, 18, 13, 4);
  const pathCenter = 9 + Math.sin(z / 14) * 3;
  const path = Math.exp(-(((x - pathCenter) / 3.5) ** 2));
  const ripple = Math.sin(x / 3.3 + z / 7) * Math.cos(z / 4.5) * 0.65;
  return Math.max(
    3,
    Math.round(5 + frontDrift + rightBank + leftDrift + cornerDrift + ripple - 2 * path),
  );
}

for (let z = -47; z <= 47; z++) {
  for (let x = -55; x <= 55; x++) {
    box(x, 0, z, 1, terrainHeight(x, z) + 1, 1, snow);
  }
}

// Snow-covered park bench behind the figures.
box(-35, 5, -36, 2, 20, 3, bark);
box(0, 5, -36, 2, 20, 3, bark);
box(-35, 17, -36, 37, 7, 2, rust);
box(-35, 24, -36, 37, 1, 3, snow);
box(-35, 11, -35, 37, 2, 8, bark);
box(-35, 13, -35, 37, 1, 8, snow);
box(-29, 14, -31, 6, 2, 4, red);
box(-28, 16, -30, 3, 1, 2, snow);

// Bundled person: separated boots, quilted coat, scarf, face and knitted hat.
box(-17, 5, -23, 5, 13, 6, navy);
box(-9, 5, -23, 5, 13, 6, navy);
box(-18, 5, -21, 6, 3, 6, dark);
box(-9, 5, -21, 6, 3, 6, dark);
box(-18, 18, -24, 16, 15, 8, coat);
box(-22, 19, -23, 4, 13, 7, coat);
box(-2, 19, -23, 4, 13, 7, coat);
box(-22, 17, -22, 4, 3, 5, skin);
box(-2, 17, -22, 4, 3, 5, skin);
for (const y of [21, 25, 29]) {
  box(-18, y, -16, 16, 1, 1, seam);
  box(-22, y, -16, 4, 1, 1, seam);
  box(-2, y, -16, 4, 1, 1, seam);
}
box(-11, 18, -15, 1, 15, 1, navy);
box(-15, 32, -23, 10, 9, 8, skin);
box(-16, 39, -24, 12, 3, 9, brown);
box(-15, 36, -15, 2, 2, 1, dark);
box(-7, 36, -15, 2, 2, 1, dark);
box(-11, 34, -14, 2, 2, 1, cream);
box(-18, 40, -25, 16, 4, 11, navy);
box(-17, 44, -24, 14, 4, 9, blue);
for (let x = -16; x <= -4; x += 3) {
  box(x, 44, -15, 1, 3, 1, scarf);
}
ball(-10, 50, -20, 2.5, 2, 2.5, snow);
box(-18, 32, -24, 16, 2, 10, scarf);
box(-10, 23, -14, 4, 10, 2, scarf);

// Sitting fox with pointed ears, pale muzzle, bib and curled tail.
ball(-34, 15, -6, 6, 10, 5, rust);
ball(-33, 15, -2, 3.5, 8, 2.5, cream);
box(-39, 5, -3, 3, 5, 5, rust);
box(-32, 5, -3, 3, 5, 5, rust);
box(-40, 24, -9, 13, 8, 8, orange);
for (let y = 0; y < 6; y++) {
  box(-40 + Math.floor(y / 2), 32 + y, -8, 4 - Math.floor(y / 2), 1, 3, rust);
  box(-31, 32 + y, -8, 4 - Math.floor(y / 2), 1, 3, rust);
}
box(-39, 28, -1, 4, 2, 1, green);
box(-31, 28, -1, 3, 2, 1, green);
box(-38, 25, -1, 9, 2, 2, cream);
box(-35, 26, 1, 3, 2, 2, dark);
ball(-27, 9, -8, 3, 4, 8, rust);
ball(-27, 7, -1, 3, 2, 3, cream);

// Bare branching tree with snow on the upper surfaces.
branch([32, 5, -28], [34, 31, -28], 3);
branch([34, 25, -28], [23, 41, -27], 2);
branch([23, 41, -27], [19, 53, -28], 1);
branch([25, 38, -27], [16, 42, -27], 1.4);
branch([34, 29, -28], [43, 43, -28], 2);
branch([43, 43, -28], [49, 52, -27], 1);
branch([40, 39, -28], [49, 43, -28], 1);
branch([34, 30, -28], [34, 55, -29], 1.7);
branch([34, 43, -29], [28, 52, -29], 1);
branch([34, 38, -28], [40, 54, -31], 1);
branch([33, 18, -28], [22, 28, -22], 1.6);
branch([22, 28, -22], [19, 36, -21], 1);
branch([35, 17, -28], [45, 25, -23], 1.5);
branch([45, 25, -23], [49, 33, -23], 1);

// Snowman replaces the mailbox on the front-right drift.
const snowmanX = 43;
const snowmanZ = 30;
const snowmanBase = terrainHeight(snowmanX, snowmanZ);
const snowmanScale = 1.5;
function snowmanBall(y, rx, ry, rz) {
  ball(
    snowmanX,
    snowmanBase + y * snowmanScale,
    snowmanZ,
    rx * snowmanScale,
    ry * snowmanScale,
    rz * snowmanScale,
    snow,
  );
}
snowmanBall(4, 7, 5, 6);
snowmanBall(11, 4.5, 4.5, 4.5);
snowmanBall(17, 3, 3, 3);
box(snowmanX - 2, snowmanBase + 27, snowmanZ + 4, 1, 2, 1, dark);
box(snowmanX + 2, snowmanBase + 27, snowmanZ + 4, 1, 2, 1, dark);
box(snowmanX, snowmanBase + 24, snowmanZ + 4, 2, 2, 5, orange);

// Sparse suspended snow: deterministic positions are shared by every render.
for (let i = 0; i < 78; i++) {
  const x = (noise(i, 7, 0) % 132) - 66;
  const z = (noise(i, 8, 0) % 120) - 60;
  const y = 12 + (noise(i, 9, 0) % 53);
  set(x, y, z, snow);
}

function normalize(v) {
  const length = Math.hypot(...v);
  return v.map((value) => value / length);
}

function cross(a, b) {
  return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
}

// Orthographic camera: identical field of view, exposure and framing at all sizes.
const forward = normalize([-0.16, -0.47, -1]);
const right = normalize(cross(forward, [0, 1, 0]));
const up = cross(right, forward);
const light = normalize([-0.55, 1, 0.65]);
const viewWidth = 182;
const target = [0, 22, 0];
const eye = target.map((v, i) => v - forward[i] * 230);

// Integer-grid DDA. The entry face determines both lighting and silhouette.
function trace(origin, direction, maxDistance = 500) {
  let start = 0;
  let end = maxDistance;
  let entryAxis = 1;
  const extent = [SIZE, HEIGHT, SIZE];
  for (let a = 0; a < 3; a++) {
    const t0 = -origin[a] / direction[a];
    const t1 = (extent[a] - origin[a]) / direction[a];
    const near = Math.min(t0, t1);
    if (near > start) {
      start = near;
      entryAxis = a;
    }
    end = Math.min(end, Math.max(t0, t1));
  }
  if (start > end) {
    return null;
  }
  const p = origin.map((v, a) => Math.floor(v + direction[a] * (start + 0.00001)));
  const step = direction.map((v) => (v > 0 ? 1 : -1));
  const delta = direction.map((v) => Math.abs(1 / v));
  const next = p.map((v, a) => (v + Number(step[a] > 0) - origin[a]) / direction[a]);
  let distance = start;
  let axis = entryAxis;
  while (
    p[0] >= 0 &&
    p[0] < SIZE &&
    p[1] >= 0 &&
    p[1] < HEIGHT &&
    p[2] >= 0 &&
    p[2] < SIZE &&
    distance <= end
  ) {
    const cell = index(...p);
    if (cells[cell]) {
      return { cell, axis, sign: -step[axis], p };
    }
    axis = next[0] < next[1] ? (next[0] < next[2] ? 0 : 2) : next[1] < next[2] ? 1 : 2;
    distance = next[axis];
    p[axis] += step[axis];
    next[axis] += delta[axis];
  }
  return null;
}

const faceCache = new Map();
function shade(hit) {
  const face = hit.axis * 2 + Number(hit.sign > 0);
  const key = hit.cell * 6 + face;
  if (faceCache.has(key)) {
    return faceCache.get(key);
  }
  const position = hit.p.map((v) => v + 0.5);
  position[hit.axis] += hit.sign * 0.501;
  const shadow = trace(position, light, 100) ? 0 : 1;
  const diffuse = Math.max(0, light[hit.axis] * hit.sign);
  // Local face-neighbour occlusion adds contact depth, independently of resolution.
  let occlusion = 0;
  for (let a = 0; a < 3; a++) {
    if (a === hit.axis) {
      continue;
    }
    for (const side of [-1, 1]) {
      const q = [...hit.p];
      q[hit.axis] += hit.sign;
      q[a] += side;
      if (
        q[0] >= 0 &&
        q[0] < SIZE &&
        q[1] >= 0 &&
        q[1] < HEIGHT &&
        q[2] >= 0 &&
        q[2] < SIZE &&
        cells[index(...q)]
      ) {
        occlusion++;
      }
    }
  }
  const ambient = (hit.axis === 1 && hit.sign > 0 ? 0.7 : 0.48) - occlusion * 0.055;
  const brightness = ambient + diffuse * shadow * 0.35;
  const rgb = palette[cells[hit.cell]].map((v, channel) =>
    Math.min(255, Math.round(v * brightness * [0.97, 0.96, 1.02][channel])),
  );
  faceCache.set(key, rgb);
  return rgb;
}

const crcTable = Uint32Array.from({ length: 256 }, (_, value) => {
  for (let i = 0; i < 8; i++) {
    value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
  }
  return value >>> 0;
});

function chunk(type, bytes) {
  const content = Buffer.concat([Buffer.from(type), bytes]);
  let crc = 0xffffffff;
  for (const byte of content) {
    crc = crcTable[(crc ^ byte) & 255] ^ (crc >>> 8);
  }
  const length = Buffer.alloc(4);
  length.writeUInt32BE(bytes.length);
  const checksum = Buffer.alloc(4);
  checksum.writeUInt32BE((crc ^ 0xffffffff) >>> 0);
  return Buffer.concat([length, content, checksum]);
}

function png(width, height, rgb) {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 2;
  const rows = Buffer.alloc((width * 3 + 1) * height);
  for (let y = 0; y < height; y++) {
    rgb.copy(rows, y * (width * 3 + 1) + 1, y * width * 3, (y + 1) * width * 3);
  }
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk("IHDR", header),
    chunk("IDAT", deflateSync(rows)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

const records = [];
await mkdir(output, { recursive: true });
await writeFile(
  join(output, "index.html"),
  await readFile(new URL("./index.html", import.meta.url)),
);
await writeFile(
  join(output, "player.html"),
  await readFile(new URL("./index.html", import.meta.url)),
);
for (const [width, height] of [
  [320, 180],
  [640, 360],
  [1920, 1080],
]) {
  const started = performance.now();
  const pixels = Buffer.alloc(width * height * 3);
  let covered = 0;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const sx = ((x + 0.5) / width - 0.5) * viewWidth;
      const sy = ((0.5 - (y + 0.5) / height) * viewWidth * height) / width;
      const origin = eye.map((v, a) => v + right[a] * sx + up[a] * sy + (a === 1 ? 0 : OFFSET));
      const hit = trace(origin, forward);
      if (hit) {
        const rgb = shade(hit);
        const at = (y * width + x) * 3;
        for (let channel = 0; channel < 3; channel++) {
          pixels[at + channel] = rgb[channel];
        }
        covered++;
      }
    }
  }
  assert(covered > width * height * 0.2 && covered < width * height * 0.9);
  const filename = `snow-${width}x${height}.png`;
  await writeFile(join(output, filename), png(width, height, pixels));
  // Compare at a common physical size using exact integer nearest scaling.
  const scale = 1920 / width;
  const enlarged = Buffer.alloc(1920 * 1080 * 3);
  for (let y = 0; y < 1080; y++) {
    for (let x = 0; x < 1920; x++) {
      const source = (Math.floor(y / scale) * width + Math.floor(x / scale)) * 3;
      const destination = (y * 1920 + x) * 3;
      pixels.copy(enlarged, destination, source, source + 3);
    }
  }
  await writeFile(join(output, `snow-${width}-display.png`), png(1920, 1080, enlarged));
  const crop = Buffer.alloc(384 * 384 * 3);
  for (let y = 0; y < 384; y++) {
    const source = ((y + 210) * 1920 + 630) * 3;
    enlarged.copy(crop, y * 384 * 3, source, source + 384 * 3);
  }
  await writeFile(join(output, `detail-${width}.png`), png(384, 384, crop));
  const record = {
    width,
    height,
    filename,
    covered,
    renderMs: Math.round(performance.now() - started),
  };
  records.push(record);
  console.log(record);
}
await writeFile(
  join(output, "report.json"),
  JSON.stringify(
    {
      renderer: "Standalone CPU voxel raycaster; not the console renderer",
      grid: [SIZE, HEIGHT, SIZE],
      occupiedCells: cells.reduce((n, v) => n + Number(v !== 0), 0),
      camera: { forward, target, viewWidth },
      sampling: "One center ray per output pixel; no antialiasing",
      lighting:
        "Fixed directional shadows and local face occlusion; cached identically across sizes",
      records,
    },
    null,
    2,
  ),
);

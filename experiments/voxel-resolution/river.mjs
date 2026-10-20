import assert from "node:assert/strict";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { deflateSync } from "node:zlib";
import { chunk, signature } from "../../tools/sdk/cartridge.mjs";

// An unbounded procedural ground field, with a finite collection of placed props.
// The prop cache bounds do not clip terrain or define a world boundary.
const output = fileURLToPath(new URL("../../build/compact-3d/resolution/river/", import.meta.url));
const PROP_SPAN = 192;
const PROP_HEIGHT = 80;
const PROP_OFFSET = PROP_SPAN / 2;
const MAX_TERRAIN_HEIGHT = 14;
const EXPLICIT_AIR = 65535;
const props = new Uint16Array(PROP_SPAN * PROP_HEIGHT * PROP_SPAN);
const palette = [[0, 0, 0]];
const color = (r, g, b) => palette.push([r, g, b]) - 1;
const grass = color(0, 153, 61);
const soil = color(107, 77, 68);
const water = color(105, 181, 226);
const stone = color(116, 137, 153);
const stoneLight = color(132, 151, 163);
const plaster = color(232, 215, 193);
const plasterTrim = color(208, 188, 166);
const roof = color(156, 5, 53);
const roofEdge = color(119, 9, 50);
const white = color(239, 238, 248);
const bark = color(122, 75, 65);
const wood = color(140, 76, 45);
const bridgeRed = color(190, 13, 47);
const bridgeDark = color(127, 8, 35);
const leaves = color(74, 192, 26);
const door = color(94, 62, 52);
const glass = color(96, 136, 165);
const hair = color(235, 194, 143);
const tunic = color(181, 79, 60);
const trousers = color(95, 67, 66);
const boots = color(116, 66, 42);
const dark = color(62, 41, 43);
const fur = color(231, 203, 167);
const muzzle = color(250, 232, 203);
const innerEar = color(214, 139, 132);

function propIndex(x, y, z) {
  return ((z + PROP_OFFSET) * PROP_HEIGHT + y) * PROP_SPAN + x + PROP_OFFSET;
}

function set(x, y, z, material) {
  x = Math.floor(x);
  y = Math.floor(y);
  z = Math.floor(z);
  assert(Math.abs(x) < PROP_OFFSET && Math.abs(z) < PROP_OFFSET && y >= 0 && y < PROP_HEIGHT);
  props[propIndex(x, y, z)] = material;
}

function box(x, y, z, w, h, d, material) {
  for (let dz = 0; dz < d; dz++) {
    for (let dy = 0; dy < h; dy++) {
      for (let dx = 0; dx < w; dx++) {
        set(x + dx, y + dy, z + dz, material);
      }
    }
  }
}

function ball(cx, cy, cz, rx, ry, rz, material) {
  for (let z = Math.floor(cz - rz); z <= cz + rz; z++) {
    for (let y = Math.floor(cy - ry); y <= cy + ry; y++) {
      for (let x = Math.floor(cx - rx); x <= cx + rx; x++) {
        if (((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 + ((z - cz) / rz) ** 2 <= 1) {
          set(x, y, z, material);
        }
      }
    }
  }
}

function noise(x, z) {
  let value = Math.imul(x, 374761393) ^ Math.imul(z, 668265263);
  value = Math.imul(value ^ (value >>> 13), 1274126177);
  return (value ^ (value >>> 16)) >>> 0;
}

function segmentDistance(x, z, ax, az, bx, bz) {
  const t = Math.max(
    0,
    Math.min(1, ((x - ax) * (bx - ax) + (z - az) * (bz - az)) / ((bx - ax) ** 2 + (bz - az) ** 2)),
  );
  return Math.hypot(x - ax - t * (bx - ax), z - az - t * (bz - az));
}

const columns = new Map();

function cobbleAt(x, z) {
  const gridRow = Math.floor(z / 5);
  for (let row = gridRow - 1; row <= gridRow + 1; row++) {
    const stagger = (row % 2) * 3;
    const gridColumn = Math.floor((x - stagger) / 6);
    for (let col = gridColumn - 1; col <= gridColumn + 1; col++) {
      const seed = noise(col, row);
      if (seed % 13 === 0) {
        continue;
      }
      const cx = col * 6 + stagger + 2.5 + ((seed % 3) - 1) * 0.6;
      const cz = row * 5 + 2 + (((seed >>> 3) % 3) - 1) * 0.5;
      const angle = (((seed >>> 10) % 7) - 3) * 0.12;
      const dx = x + 0.5 - cx;
      const dz = z + 0.5 - cz;
      const u = dx * Math.cos(angle) + dz * Math.sin(angle);
      const v = -dx * Math.sin(angle) + dz * Math.cos(angle);
      const rx = 2 + ((seed >>> 5) % 3) * 0.25;
      const rz = 1.45 + ((seed >>> 7) % 3) * 0.25;
      const radius = (u / rx) ** 2 + (v / rz) ** 2;
      const chipped = noise(x, z) % 7 === 0 ? 0.15 : 0;
      if (radius < 1 - chipped) {
        return {
          height: radius < 0.35 && seed % 3 === 0 ? 2 : 1,
          material: seed % 3 === 0 ? stoneLight : stone,
        };
      }
    }
  }
  return null;
}

function terrainColumn(x, z) {
  let row = columns.get(x);
  if (!row) {
    row = new Map();
    columns.set(x, row);
  }
  if (row.has(z)) {
    return row.get(z);
  }
  const center = (z < -10 ? 29 : 27 + (z - 18) * 0.28) + Math.sin(z / 13) * 1.2;
  const halfWidth = 9 + 15 * Math.exp(-(((z + 26) / 21) ** 4));
  const shoreline = Math.abs(x - center) - halfWidth + Math.sin(z / 4.5) * 0.7;
  const isWater = shoreline < 0;
  const raised = x >= -65 && x < -13 && z >= -46 && z < 6;
  const rightHill = 3 * Math.exp(-(((x - 55) / 18) ** 2 + ((z - 42) / 25) ** 2));
  const leftHill = 2 * Math.exp(-(((x + 58) / 23) ** 2 + ((z - 30) / 25) ** 2));
  const landHeight = 7 + Math.round(rightHill + leftHill);
  const ground = isWater ? 4 : raised ? 12 : Math.min(landHeight, 5 + Math.floor(shoreline / 2.5));
  let top = ground;
  let material = isWater ? water : grass;
  const path = Math.min(
    segmentDistance(x, z, -200, 104, -26, 40),
    segmentDistance(x, z, -26, 40, -4, 18),
    segmentDistance(x, z, -4, 18, 200, 18),
  );
  const gatePath = x > -43 && x < -30 && z >= -15 && z <= 18;
  const pathWidth = 8 + (noise(Math.floor(x / 8), Math.floor(z / 8)) % 3);
  if (!isWater && (path < pathWidth || gatePath)) {
    const cobble = cobbleAt(x, z);
    if (cobble) {
      top += cobble.height;
      material = cobble.material;
    }
  }
  const grassDepth = 1 + (noise(Math.floor(x / 2), Math.floor(z / 2)) % 3);
  const outsideLawn = Math.max(-65 - x, x + 14, -46 - z, z - 5, 0);
  const fringe = !raised && !isWater && !gatePath && outsideLawn <= 2 && noise(x, z) % 4 !== 0;
  const column = {
    top,
    ground,
    material,
    isWater,
    grassDepth,
    fringeBottom: fringe ? 11 + (noise(x, z) % 2) : Infinity,
  };
  row.set(z, column);
  return column;
}

function voxel(x, y, z) {
  if (y < 0 || y >= PROP_HEIGHT) {
    return 0;
  }
  if (x > -PROP_OFFSET && x < PROP_OFFSET && z > -PROP_OFFSET && z < PROP_OFFSET) {
    const material = props[propIndex(x, y, z)];
    if (material) {
      return material === EXPLICIT_AIR ? 0 : material;
    }
  }
  if (y > MAX_TERRAIN_HEIGHT) {
    return 0;
  }
  const column = terrainColumn(x, z);
  if (y > column.top) {
    return y >= column.fringeBottom && y <= 12 ? grass : 0;
  }
  if (column.isWater) {
    return y === column.top ? water : soil;
  }
  if (y > column.ground) {
    return column.material;
  }
  return y > column.ground - column.grassDepth ? grass : soil;
}

// Cream cottage on a raised lawn, with a stepped hip roof and recessed doorway.
box(-58, 13, -39, 35, 20, 24, plaster);
box(-59, 13, -40, 2, 20, 26, plasterTrim);
box(-25, 13, -40, 2, 20, 26, plasterTrim);
box(-46, 13, -21, 7, 14, 7, EXPLICIT_AIR);
box(-46, 13, -22, 7, 14, 1, door);
box(-45, 13, -19, 5, 1, 5, wood);
box(-33, 21, -15, 6, 8, 1, glass);
box(-31, 21, -14, 1, 8, 1, bark);
box(-33, 24, -14, 6, 1, 1, bark);
box(-34, 20, -15, 8, 1, 2, plasterTrim);
for (let layer = 0; layer < 13; layer++) {
  const inset = Math.floor(layer * 0.8);
  box(
    -62 + inset,
    33 + layer,
    -43 + inset,
    43 - inset * 2,
    1,
    32 - inset * 2,
    layer % 3 === 0 ? roofEdge : roof,
  );
}

// White garden fence, including a front gate opening onto the stone path.
for (let z = -44; z <= 5; z += 7) {
  box(-63, 13, z, 2, 10, 2, white);
  box(-15, 13, z, 2, 10, 2, white);
}
for (const y of [16, 20]) {
  box(-63, y, -44, 1, 1, 51, white);
  box(-14, y, -44, 1, 1, 51, white);
  box(-63, y, 5, 20, 1, 1, white);
  box(-30, y, 5, 17, 1, 1, white);
}
for (const x of [-63, -44, -30, -15]) {
  box(x, 13, 4, 2, 10, 3, white);
}

// Broad leafy tree beside the pond, with visible trunk and exposed roots.
box(-9, 7, -33, 5, 22, 5, bark);
box(-14, 8, -31, 15, 2, 2, bark);
box(-8, 8, -37, 2, 2, 13, bark);
ball(-7, 34, -31, 13, 10, 12, leaves);
ball(-7, 42, -31, 10, 10, 9, leaves);
ball(-8, 49, -32, 6, 6, 6, leaves);

// Arched red bridge crosses the stream, continuing the path to the right edge.
for (let x = 14; x <= 42; x++) {
  const arch = Math.round(4 * Math.sin(((x - 14) / 28) * Math.PI));
  const y = 8 + arch;
  box(x, y, 12, 1, 2, 13, x % 3 === 0 ? bark : wood);
  for (const z of [11, 25]) {
    box(x, y + 6, z, 1, 2, 2, bridgeRed);
    box(x, y + 2, z, 1, 2, 2, bridgeDark);
    if ((x - 14) % 7 === 0) {
      box(x, y, z, 2, 9, 2, bridgeRed);
    }
  }
}
for (const x of [14, 41]) {
  box(x, 4, 11, 2, 7, 16, bridgeDark);
}

// Humanoid rabbit adventurer, with long ears, pale muzzle, tail and red tunic.
box(-7, 8, 18, 2, 5, 3, trousers);
box(-3, 8, 18, 2, 5, 3, trousers);
box(-7, 8, 20, 2, 2, 3, boots);
box(-3, 8, 20, 2, 2, 3, boots);
box(-8, 13, 17, 8, 7, 5, tunic);
box(-9, 14, 18, 2, 4, 3, fur);
box(0, 14, 18, 2, 4, 3, fur);
ball(-4, 24, 19, 4, 4, 3.5, fur);
box(-8, 27, 17, 3, 11, 3, fur);
box(-2, 27, 17, 3, 13, 3, fur);
box(-7, 29, 20, 1, 8, 1, innerEar);
box(-1, 29, 20, 1, 10, 1, innerEar);
box(-7, 38, 17, 2, 1, 3, fur);
box(-1, 40, 17, 2, 1, 3, fur);
box(-6, 25, 22, 1, 2, 1, dark);
box(-2, 25, 22, 1, 2, 1, dark);
ball(-4, 22, 22, 2.5, 2, 2, muzzle);
set(-4, 23, 24, innerEar);
ball(0, 14, 16, 2.5, 2.5, 2.5, muzzle);
box(-10, 12, 21, 1, 6, 1, bark);
box(-12, 18, 21, 5, 1, 1, wood);
box(-10, 19, 21, 1, 13, 1, white);
box(1, 13, 20, 2, 6, 4, hair);

function normalize(v) {
  const length = Math.hypot(...v);
  return v.map((value) => value / length);
}

function cross(a, b) {
  return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
}

const forward = normalize([-0.12, -0.72, -1]);
const right = normalize(cross(forward, [0, 1, 0]));
const up = cross(right, forward);
const light = normalize([-0.6, 1, 0.6]);
const target = [0, 24, 0];
const eye = target.map((v, a) => v - forward[a] * 260);
const viewWidth = 180;

function trace(origin, direction, maxDistance = 500) {
  const near = -origin[1] / direction[1];
  const far = (PROP_HEIGHT - origin[1]) / direction[1];
  const start = Math.max(0, Math.min(near, far));
  const end = Math.min(maxDistance, Math.max(near, far));
  if (start > end) {
    return null;
  }
  const p = origin.map((v, a) => Math.floor(v + direction[a] * (start + 0.00001)));
  const step = direction.map((v) => (v > 0 ? 1 : -1));
  const delta = direction.map((v) => Math.abs(1 / v));
  const next = p.map((v, a) => (v + Number(step[a] > 0) - origin[a]) / direction[a]);
  let distance = start;
  let axis = 1;
  while (p[1] >= 0 && p[1] < PROP_HEIGHT && distance <= end) {
    const material = voxel(...p);
    if (material) {
      return { p, axis, sign: -step[axis], material };
    }
    axis = next[0] < next[1] ? (next[0] < next[2] ? 0 : 2) : next[1] < next[2] ? 1 : 2;
    distance = next[axis];
    p[axis] += step[axis];
    next[axis] += delta[axis];
  }
  return null;
}

const faces = new Map();
function shade(hit) {
  const key = `${hit.p.join(",")},${hit.axis},${hit.sign}`;
  if (faces.has(key)) {
    return faces.get(key);
  }
  const position = hit.p.map((v) => v + 0.5);
  position[hit.axis] += hit.sign * 0.501;
  const shadow = trace(position, light, 100) ? 0 : 1;
  let occlusion = 0;
  for (let axis = 0; axis < 3; axis++) {
    if (axis === hit.axis) {
      continue;
    }
    for (const side of [-1, 1]) {
      const p = [...hit.p];
      p[hit.axis] += hit.sign;
      p[axis] += side;
      occlusion += Number(voxel(...p) !== 0);
    }
  }
  const ambient = (hit.axis === 1 && hit.sign > 0 ? 0.74 : 0.5) - occlusion * 0.05;
  const brightness = ambient + 0.3 * shadow * Math.max(0, light[hit.axis] * hit.sign);
  const rgb = palette[hit.material].map((v) => Math.min(255, Math.round(v * brightness)));
  faces.set(key, rgb);
  return rgb;
}

function png(width, height, pixels) {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 2;
  const scanlines = Buffer.alloc((width * 3 + 1) * height);
  for (let y = 0; y < height; y++) {
    pixels.copy(scanlines, y * (width * 3 + 1) + 1, y * width * 3, (y + 1) * width * 3);
  }
  return Buffer.concat([
    signature,
    chunk("IHDR", header),
    chunk("IDAT", deflateSync(scanlines)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

await mkdir(output, { recursive: true });
const page = await readFile(new URL("./river.html", import.meta.url));
await writeFile(join(output, "index.html"), page);
await writeFile(join(output, "player.html"), page);
const records = [];
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
      const origin = eye.map((v, a) => v + right[a] * sx + up[a] * sy);
      const hit = trace(origin, forward);
      assert(hit, "Procedural terrain must fill every output pixel");
      pixels.set(shade(hit), (y * width + x) * 3);
      covered++;
    }
  }
  const filename = `river-${width}x${height}.png`;
  await writeFile(join(output, filename), png(width, height, pixels));
  const enlarged = Buffer.alloc(1920 * 1080 * 3);
  const scale = 1920 / width;
  for (let y = 0; y < 1080; y++) {
    for (let x = 0; x < 1920; x++) {
      const source = (Math.floor(y / scale) * width + Math.floor(x / scale)) * 3;
      pixels.copy(enlarged, (y * 1920 + x) * 3, source, source + 3);
    }
  }
  await writeFile(join(output, `river-${width}-display.png`), png(1920, 1080, enlarged));
  const detail = Buffer.alloc(384 * 384 * 3);
  for (let y = 0; y < 384; y++) {
    const source = ((y + 480) * 1920 + 720) * 3;
    enlarged.copy(detail, y * 384 * 3, source, source + 384 * 3);
  }
  await writeFile(join(output, `detail-${width}.png`), png(384, 384, detail));
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
      terrain: "Procedural in world X/Z; no horizontal world boundary",
      propCache: [PROP_SPAN, PROP_HEIGHT, PROP_SPAN],
      camera: { forward, target, viewWidth },
      sampling: "One center ray per pixel; no antialiasing",
      records,
    },
    null,
    2,
  ),
);

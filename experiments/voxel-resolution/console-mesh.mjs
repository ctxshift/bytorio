import assert from "node:assert/strict";

// Merge only adjacent coplanar unit faces with identical baked colors. This
// changes triangle count without changing the original opaque surface field.
export function mergeFaces(bytes) {
  const groups = new Map();
  assert.equal(bytes.length % 96, 0);
  for (let offset = 0; offset < bytes.length; offset += 96) {
    const positions = [0, 1, 2, 5].map((i) =>
      [0, 1, 2].map((j) => bytes.readFloatLE(offset + i * 16 + j * 4)),
    );
    const axis = [0, 1, 2].find((i) => positions.every((p) => p[i] === positions[0][i]));
    assert.notEqual(axis, undefined);
    const axes = [0, 1, 2].filter((i) => i !== axis);
    const a = positions[1].map((v, i) => v - positions[0][i]);
    const b = positions[2].map((v, i) => v - positions[0][i]);
    const cross = [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
    const color = bytes.readUInt32LE(offset + 12);
    for (let i = 0; i < 6; i++) {
      assert.equal(bytes.readUInt32LE(offset + i * 16 + 12), color);
    }
    const plane = positions[0][axis];
    const x = Math.min(...positions.map((p) => p[axes[0]]));
    const y = Math.min(...positions.map((p) => p[axes[1]]));
    assert.equal(Math.max(...positions.map((p) => p[axes[0]])) - x, 1);
    assert.equal(Math.max(...positions.map((p) => p[axes[1]])) - y, 1);
    const sign = Math.sign(cross[axis]);
    assert(sign !== 0, "degenerate surface triangle");
    const key = [axis, plane, color, sign].join(",");
    if (!groups.has(key)) {
      groups.set(key, { axis, plane, color, sign, cells: new Set() });
    }
    const cells = groups.get(key).cells;
    assert(!cells.has(`${x},${y}`), "duplicate surface face");
    cells.add(`${x},${y}`);
  }
  const rectangles = [];
  let coveredFaces = 0;
  for (const { axis, plane, color, sign, cells } of groups.values()) {
    for (const cell of cells) {
      const [x, y] = cell.split(",").map(Number);
      let width = 1;
      while (cells.has(`${x + width},${y}`)) {
        width++;
      }
      let height = 1;
      while (
        Array.from({ length: width }, (_, dx) => cells.has(`${x + dx},${y + height}`)).every(
          Boolean,
        )
      ) {
        height++;
      }
      for (let dy = 0; dy < height; dy++) {
        for (let dx = 0; dx < width; dx++) {
          assert(cells.delete(`${x + dx},${y + dy}`));
        }
      }
      coveredFaces += width * height;
      rectangles.push({ axis, plane, color, sign, x, y, width, height });
    }
  }
  assert.equal(coveredFaces, bytes.length / 96);
  return rectangles;
}

export function encodeScene(world, rabbit) {
  const colors = [...new Set([...world, ...rabbit].map((face) => face.color))];
  const palette = new Map(colors.map((color, i) => [color, i]));
  const bytes = Buffer.alloc(12 + colors.length * 4 + (world.length + rabbit.length) * 13);
  bytes.writeUInt32LE(world.length, 0);
  bytes.writeUInt32LE(rabbit.length, 4);
  bytes.writeUInt32LE(colors.length, 8);
  colors.forEach((color, i) => bytes.writeUInt32LE(color, 12 + i * 4));
  let at = 12 + colors.length * 4;
  for (const face of [...world, ...rabbit]) {
    bytes[at] = face.axis + (face.sign < 0 ? 4 : 0);
    bytes.writeInt16LE(face.plane, at + 1);
    bytes.writeInt16LE(face.x, at + 3);
    bytes.writeInt16LE(face.y, at + 5);
    bytes.writeUInt16LE(face.width, at + 7);
    bytes.writeUInt16LE(face.height, at + 9);
    bytes.writeUInt16LE(palette.get(face.color), at + 11);
    at += 13;
  }
  return bytes;
}

// Small bounded LZ stream for an embedded fixture, not a cartridge format.
// Literal token: length-1 (0..127), bytes. Match: length-3+128, u16 distance.
export function compressScene(bytes) {
  // A bounded deeper search keeps the embedded fixture below the Luau source
  // budget without changing decoded geometry or the runtime format.
  const searchCandidates = 64;
  const output = [];
  const recent = new Map();
  let literals = [];
  const flush = () => {
    if (literals.length) {
      output.push(literals.length - 1, ...literals);
    }
    literals = [];
  };
  for (let at = 0; at < bytes.length;) {
    const key = bytes.subarray(at, at + 3).toString("hex");
    const candidates = recent.get(key) || [];
    let previous;
    let length = 0;
    for (const candidate of candidates) {
      if (at - candidate > 65535) {
        continue;
      }
      let matched = 0;
      while (
        matched < 130 &&
        at + matched < bytes.length &&
        bytes[candidate + matched] === bytes[at + matched]
      ) {
        matched++;
      }
      if (matched > length) {
        previous = candidate;
        length = matched;
      }
    }
    if (length >= 4) {
      flush();
      const distance = at - previous;
      output.push(128 + length - 3, distance & 255, distance >> 8);
      for (let i = 0; i < length; i++) {
        remember(at + i);
      }
      at += length;
    } else {
      remember(at);
      literals.push(bytes[at++]);
      if (literals.length === 128) {
        flush();
      }
    }
  }
  flush();
  return Buffer.from(output);

  function remember(at) {
    const key = bytes.subarray(at, at + 3).toString("hex");
    const candidates = recent.get(key) || [];
    candidates.unshift(at);
    if (candidates.length > searchCandidates) {
      candidates.pop();
    }
    recent.set(key, candidates);
  }
}

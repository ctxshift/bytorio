import assert from "node:assert/strict";
import { test } from "node:test";
import { mergeFaces, encodeScene, compressScene } from "./console-mesh.mjs";

function quad(x, y, color = 0xff123456, reversed = false) {
  const bytes = Buffer.alloc(96);
  const corners = [
    [x, y, 0],
    [x + 1, y, 0],
    [x + 1, y + 1, 0],
    [x, y + 1, 0],
  ];
  const order = reversed ? [0, 2, 1, 0, 3, 2] : [0, 1, 2, 0, 2, 3];
  order.forEach((index, i) => {
    corners[index].forEach((value, axis) => bytes.writeFloatLE(value, i * 16 + axis * 4));
    bytes.writeUInt32LE(color, i * 16 + 12);
  });
  return bytes;
}

test("coplanar rectangles preserve area, plane, color and winding", () => {
  const merged = mergeFaces(Buffer.concat([quad(0, 0), quad(1, 0), quad(0, 1), quad(1, 1)]));
  assert.deepEqual(merged, [
    { axis: 2, plane: 0, color: 0xff123456, sign: 1, x: 0, y: 0, width: 2, height: 2 },
  ]);
  const split = mergeFaces(
    Buffer.concat([quad(0, 0), quad(1, 0, 0xff998877), quad(0, 1, 0xff123456, true)]),
  );
  assert.equal(split.length, 3);
  assert.deepEqual(
    split.map((face) => face.sign),
    [1, 1, -1],
  );
  assert.throws(() => mergeFaces(Buffer.concat([quad(0, 0), quad(0, 0)])), /duplicate/);
});

test("scene records have independent known coordinates and palette entries", () => {
  const faces = mergeFaces(quad(-3, 2));
  const encoded = encodeScene(faces, []);
  assert.equal(encoded.length, 29);
  assert.equal(encoded.readUInt32LE(0), 1);
  assert.equal(encoded.readUInt32LE(4), 0);
  assert.equal(encoded.readUInt32LE(8), 1);
  assert.equal(encoded.readUInt32LE(12), 0xff123456);
  assert.equal(encoded[16], 2);
  assert.equal(encoded.readInt16LE(19), -3);
  assert.equal(encoded.readInt16LE(21), 2);
  assert.equal(encoded.readUInt16LE(23), 1);
  assert.equal(encoded.readUInt16LE(25), 1);
  assert.equal(encoded.readUInt16LE(27), 0);
});

function decode(bytes) {
  const output = [];
  let at = 0;
  while (at < bytes.length) {
    const token = bytes[at++];
    if (token < 128) {
      for (let i = 0; i <= token; i++) {
        output.push(bytes[at++]);
      }
    } else {
      const distance = bytes.readUInt16LE(at);
      at += 2;
      assert(distance > 0 && distance <= output.length);
      for (let i = 0; i < token - 125; i++) {
        output.push(output[output.length - distance]);
      }
    }
  }
  assert.equal(at, bytes.length);
  return Buffer.from(output);
}

test("fixture compression round-trips literals, overlapping matches and window boundaries", () => {
  for (const bytes of [
    Buffer.alloc(0),
    Buffer.from("a"),
    Buffer.alloc(1024, 31),
    Buffer.from(Array.from({ length: 70000 }, (_, i) => (i * 73 + (i >> 8)) & 255)),
  ]) {
    assert.deepEqual(decode(compressScene(bytes)), bytes);
  }
});

test("fixture compression retains useful matches behind common three-byte prefixes", () => {
  const records = Array.from({ length: 48 }, (_, index) =>
    Buffer.concat([Buffer.from([1, 2, 3, index]), Buffer.alloc(64, index + 32)]),
  );
  const bytes = Buffer.concat([...records, records[0]]);
  const compressed = compressScene(bytes);
  assert.deepEqual(decode(compressed), bytes);
  assert(compressed.length <= 435, "older matches must remain available within the bounded search");
});

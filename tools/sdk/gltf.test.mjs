import assert from "node:assert/strict";
import { test, after } from "node:test";
import { mkdir, mkdtemp, readFile, writeFile, readdir, rm, symlink } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { deflateSync } from "node:zlib";
import { readGltf, decodeTexture, IMPORT_LIMITS } from "./gltf.mjs";
import { importModel } from "./import-model.mjs";
import { modelSources } from "./model-source.mjs";
import { signature, chunk } from "./cartridge.mjs";

await mkdir("build", { recursive: true });
const root = await mkdtemp(resolve("build/model-unit-"));
const original = JSON.parse(await readFile("examples/models/assets/rigid-kart.gltf"));

test("generated asset namespaces depend on content rather than report metadata", async () => {
  const model = await readGltf("examples/models/assets/rigid-kart.gltf");
  const sources = modelSources(model);
  const reported = structuredClone(model);
  reported.report.sourceBytes = { "model.odin": 1234 };
  assert.deepEqual(modelSources(reported), sources);
  const changed = structuredClone(model);
  changed.primitives[0].vertices[0].position[0] += 1 / 64;
  const namespace = (source) => source.match(/^package (\w+)/m)[1];
  assert.notEqual(namespace(modelSources(changed)["model.odin"]), namespace(sources["model.odin"]));
});
after(async () => {
  assert.equal(dirname(root), resolve("build"));
  await rm(root, { recursive: true, force: true });
});

async function fixture(name, edit = () => {}) {
  const value = structuredClone(original);
  await edit(value);
  const file = resolve(root, name + ".gltf");
  await writeFile(file, JSON.stringify(value));
  return file;
}
function binary(value) {
  return Buffer.from(value.buffers[0].uri.split(",")[1], "base64");
}
function replaceBinary(value, bytes) {
  value.buffers[0].uri = "data:application/octet-stream;base64," + bytes.toString("base64");
  value.buffers[0].byteLength = bytes.length;
}
function near(actual, expected) {
  assert.equal(actual.length, expected.length);
  actual.forEach((value, index) =>
    assert(
      Math.abs(value - expected[index]) < 0.000001,
      `${index}: ${value} != ${expected[index]}`,
    ),
  );
}
function png(width, height, raw, type = 6) {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = type;
  return Buffer.concat([
    signature,
    chunk("IHDR", header),
    chunk("IDAT", deflateSync(Buffer.from(raw))),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}
function glb(value, bytes) {
  const doc = structuredClone(value);
  delete doc.buffers[0].uri;
  const json = Buffer.from(JSON.stringify(doc));
  const paddedJson = Buffer.alloc(Math.ceil(json.length / 4) * 4, 32);
  json.copy(paddedJson);
  const paddedBinary = Buffer.alloc(Math.ceil(bytes.length / 4) * 4);
  bytes.copy(paddedBinary);
  const result = Buffer.alloc(12 + 8 + paddedJson.length + 8 + paddedBinary.length);
  result.writeUInt32LE(0x46546c67);
  result.writeUInt32LE(2, 4);
  result.writeUInt32LE(result.length, 8);
  result.writeUInt32LE(paddedJson.length, 12);
  result.writeUInt32LE(0x4e4f534a, 16);
  paddedJson.copy(result, 20);
  result.writeUInt32LE(paddedBinary.length, 20 + paddedJson.length);
  result.writeUInt32LE(0x004e4942, 24 + paddedJson.length);
  paddedBinary.copy(result, 28 + paddedJson.length);
  return result;
}

test("independent geometry, hierarchy, winding, UV, tint, alpha and byte counts", async () => {
  const result = await readGltf(await fixture("known"));
  assert.deepEqual(
    result.nodes.map(({ name, parent, primitives }) => ({ name, parent, primitives })),
    [
      { name: "body", parent: -1, primitives: [0] },
      { name: "wheel", parent: 0, primitives: [1] },
    ],
  );
  assert.deepEqual(result.primitives[0].vertices[0], {
    position: [-1, 0, 0.5],
    uv: [0, 1],
    color: 0xffff80ff,
  });
  assert.deepEqual(result.primitives[0].indices.slice(0, 6), [0, 2, 1, 0, 3, 2]);
  near(result.nodes[0].local, [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 0, -2, 1]);
  near(result.nodes[1].local, [0, 0, 2, 0, 0, 1, 0, 0, -1, 0, 0, 0, -0.7, 0.2, -0.9, 1]);
  near(result.nodes[1].world, [0, 0, 2, 0, 0, 1, 0, 0, -1, 0, 0, 0, 0.3, 0.2, -2.9, 1]);
  assert.deepEqual(
    result.materials[0].pixels,
    [188, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 188, 255, 255, 255],
  );
  assert.deepEqual(
    result.materials[1].pixels,
    [255, 0, 0, 255, 0, 128, 0, 128, 0, 0, 0, 0, 255, 255, 255, 255],
  );
  assert.equal(result.materials[1].cutoff, 128);
  assert.equal(result.materials[0].addressU, "clamp");
  assert.equal(result.materials[0].addressV, "repeat");
  assert.deepEqual(
    [result.report.uploadBytes, result.report.vertices, result.report.triangles],
    [936, 28, 14],
  );
  assert.equal(result.minimumSdk, "0.5.0");
});

test("GLB, embedded image bufferViews, external files and JSON imports have identical model data", async () => {
  const normal = await readGltf(await fixture("normal"));
  const value = structuredClone(original);
  const geometry = binary(value);
  const padding = Buffer.alloc(Math.ceil(geometry.length / 4) * 4);
  geometry.copy(padding);
  const image = Buffer.from(value.images[0].uri.split(",")[1], "base64");
  const combined = Buffer.concat([padding, image]);
  value.bufferViews.push({ buffer: 0, byteOffset: padding.length, byteLength: image.length });
  value.images[0] = { bufferView: value.bufferViews.length - 1, mimeType: "image/png" };
  value.buffers[0].byteLength = combined.length;
  await writeFile(resolve(root, "fixture.glb"), glb(value, combined));
  const packed = await readGltf(resolve(root, "fixture.glb"));
  for (const field of ["nodes", "primitives", "materials", "minimumSdk"]) {
    assert.deepEqual(packed[field], normal[field]);
  }
  await writeFile(resolve(root, "geometry.bin"), geometry);
  await writeFile(resolve(root, "art.png"), image);
  const external = await readGltf(
    await fixture("external", (v) => {
      v.buffers[0].uri = "geometry.bin";
      v.images[0].uri = "art.png";
    }),
  );
  for (const field of ["nodes", "primitives", "materials"]) {
    assert.deepEqual(external[field], normal[field]);
  }
});

test("PNG filters, RGB expansion, dimensions, CRC and decompression limits", () => {
  const pixels = [10, 20, 30, 255, 40, 50, 60, 128];
  assert.deepEqual(decodeTexture(png(2, 1, [1, 10, 20, 30, 255, 30, 30, 30, 129])).pixels, pixels);
  assert.deepEqual(
    decodeTexture(png(2, 2, [0, ...pixels, 2, 60, 60, 60, 0, 60, 60, 60, 192])).pixels,
    [...pixels, 70, 80, 90, 255, 100, 110, 120, 64],
  );
  assert.deepEqual(decodeTexture(png(2, 1, [3, 10, 20, 30, 255, 35, 40, 45, 1])).pixels, pixels);
  assert.deepEqual(decodeTexture(png(2, 1, [4, 10, 20, 30, 255, 30, 30, 30, 129])).pixels, pixels);
  assert.deepEqual(decodeTexture(png(1, 1, [0, 12, 34, 56], 2)).pixels, [12, 34, 56, 255]);
  assert.throws(() => decodeTexture(png(1025, 1, [0])), /dimensions/);
  assert.throws(() => decodeTexture(png(1, 1, Array(100).fill(0))), /larger|size|length/i);
  const corrupt = png(1, 1, [0, 1, 2, 3, 255]);
  corrupt[corrupt.length - 1] ^= 1;
  assert.throws(() => decodeTexture(corrupt), /checksum/);
});

const rejected = [
  ["accessor-range", (v) => (v.accessors[0].count = 25), /range/],
  ["bad-stride", (v) => (v.bufferViews[0].byteStride = 23), /stride/],
  ["misaligned", (v) => (v.accessors[0].byteOffset = 1), /alignment/],
  ["sparse", (v) => (v.accessors[0].sparse = {}), /sparse/],
  ["wrong-type", (v) => (v.accessors[0].componentType = 5123), /POSITION/],
  ["bad-attributes", (v) => (v.meshes[0].primitives[0].attributes.TEXCOORD_1 = 1), /attribute/],
  ["count-mismatch", (v) => (v.accessors[1].count = 23), /count/],
  [
    "index-range",
    (v) => {
      const b = binary(v);
      b.writeUInt16LE(24, 576);
      replaceBinary(v, b);
    },
    /indices/,
  ],
  [
    "not-finite",
    (v) => {
      const b = binary(v);
      b.writeFloatLE(NaN, 0);
      replaceBinary(v, b);
    },
    /POSITION/,
  ],
  ["extensions", (v) => (v.extensionsUsed = ["KHR_draco_mesh_compression"]), /extensions/],
  [
    "nested-extension",
    (v) => (v.materials[0].extensions = { KHR_materials_unlit: {} }),
    /extensions/,
  ],
  ["skinning", (v) => (v.skins = [{}]), /skins/],
  ["animation", (v) => (v.animations = [{}]), /animations/],
  ["morph", (v) => (v.meshes[0].primitives[0].targets = []), /static/],
  ["triangle-strip", (v) => (v.meshes[0].primitives[0].mode = 5), /TRIANGLES/],
  ["blend", (v) => (v.materials[0].alphaMode = "BLEND"), /OPAQUE/],
  ["linear-sampler", (v) => (v.samplers[0].minFilter = 9987), /nearest/],
  ["mirrored-wrap", (v) => (v.samplers[0].wrapS = 33648), /wrap/],
  ["pbr-map", (v) => (v.materials[0].normalTexture = { index: 0 }), /normal/],
  ["cycle", (v) => (v.nodes[1].children = [0]), /cycle/],
  ["duplicate-parent", (v) => v.scenes[0].nodes.push(1), /parents/],
  ["duplicate-name", (v) => (v.nodes[1].name = "body"), /unique/],
  ["matrix-trs", (v) => (v.nodes[0].matrix = Array(16).fill(0)), /mix matrix/],
  ["singular", (v) => (v.nodes[0].scale = [0, 1, 1]), /singular/],
  ["non-unit-quaternion", (v) => (v.nodes[0].rotation = [0, 0, 0, 2]), /quaternion/],
  ["coordinate-bound", (v) => (v.nodes[0].translation = [1000000, 0, 0]), /translation/],
  ["network-uri", (v) => (v.buffers[0].uri = "https://invalid.example/data.bin"), /relative/],
  ["absolute-uri", (v) => (v.buffers[0].uri = "/geometry.bin"), /relative/],
  ["windows-uri", (v) => (v.buffers[0].uri = "X:/geometry.bin"), /relative/],
  [
    "bad-base64",
    (v) => (v.buffers[0].uri = "data:application/octet-stream;base64,AA=A"),
    /data URI/,
  ],
];
for (const [name, edit, expected] of rejected) {
  test(`reject ${name}`, async () =>
    assert.rejects(() => fixture(name, edit).then(readGltf), expected));
}

test("external traversal, encoded traversal and symlink escapes are rejected", async () => {
  const inner = resolve(root, "inner");
  await mkdir(inner);
  await writeFile(resolve(root, "outside.bin"), binary(original));
  for (const uri of ["../outside.bin", "%2e%2e/outside.bin"]) {
    const value = structuredClone(original);
    value.buffers[0].uri = uri;
    const path = resolve(inner, "traversal.gltf");
    await writeFile(path, JSON.stringify(value));
    await assert.rejects(readGltf(path), /escapes/);
  }
  await symlink(root, resolve(inner, "link"), process.platform === "win32" ? "junction" : "dir");
  const value = structuredClone(original);
  value.buffers[0].uri = "link/outside.bin";
  const path = resolve(inner, "linked.gltf");
  await writeFile(path, JSON.stringify(value));
  await assert.rejects(readGltf(path), /escapes/);
});

test("deterministic source publication preserves previous files on invalid import", async () => {
  const file = await fixture("published"),
    output = resolve(root, "generated");
  await importModel(file, output);
  const snapshot = await Promise.all(
    ["model.json", "model.luau", "model.odin"].map((name) => readFile(resolve(output, name))),
  );
  await importModel(file, output);
  for (const [i, name] of ["model.json", "model.luau", "model.odin"].entries()) {
    assert.deepEqual(await readFile(resolve(output, name)), snapshot[i]);
  }
  await writeFile(file, JSON.stringify({ ...original, animations: [{}] }));
  await assert.rejects(importModel(file, output), /animations/);
  assert.deepEqual(await readFile(resolve(output, "model.json")), snapshot[0]);
  const safe = await fixture("safe");
  await writeFile(resolve(output, "handwritten.txt"), "keep");
  await assert.rejects(importModel(safe, output), /non-generated/);
  assert.equal(await readFile(resolve(output, "handwritten.txt"), "utf8"), "keep");
  assert(
    !(await readdir(root)).some(
      (name) => name.includes(".byt-stage-") || name.includes(".byt-backup-"),
    ),
  );
});

test("declared import limits preserve runtime headroom", () => {
  assert.equal(IMPORT_LIMITS.uploadBytes, 524288);
  assert.equal(IMPORT_LIMITS.sourceBytes, 131072);
});

test("four-byte attribute alignment and reserved indices are checked", async () => {
  await assert.rejects(
    readGltf(
      await fixture("short-alignment", (value) => {
        Object.assign(value.accessors[1], {
          componentType: 5123,
          normalized: true,
          byteOffset: 14,
        });
      }),
    ),
    /alignment/,
  );
  await assert.rejects(
    readGltf(
      await fixture("packed-color-alignment", (value) => {
        const old = binary(value);
        const bytes = Buffer.alloc(736 + 24 * 3, 255);
        old.copy(bytes);
        value.bufferViews.push({ buffer: 0, byteOffset: 736, byteLength: 24 * 3 });
        Object.assign(value.accessors[2], { bufferView: 4, byteOffset: 0, type: "VEC3" });
        replaceBinary(value, bytes);
      }),
    ),
    /alignment/,
  );
  await assert.rejects(
    readGltf(
      await fixture("reserved-index", (value) => {
        const bytes = binary(value);
        bytes[728] = 255;
        replaceBinary(value, bytes);
      }),
    ),
    /primitive-restart/,
  );
});

test("malformed root and object arrays report useful diagnostics", async () => {
  const file = resolve(root, "null.gltf");
  await writeFile(file, "null");
  await assert.rejects(readGltf(file), /root must be an object/);
  await assert.rejects(
    readGltf(await fixture("null-node", (value) => (value.nodes[0] = null))),
    /nodes entry/,
  );
  await assert.rejects(
    readGltf(
      await fixture("emissive-type", (value) => (value.materials[0].emissiveFactor = "bad")),
    ),
    /emissive factor/,
  );
});

test("matrix transforms and reused geometry retain stable names and shared resources", async () => {
  const result = await readGltf(
    await fixture("matrix-instance", (value) => {
      delete value.nodes[0].translation;
      value.nodes[0].matrix = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 0, 2, 1];
      value.nodes[0].children.push(2);
      value.nodes.push({ name: "second-wheel", mesh: 1, translation: [0, 0, -1] });
    }),
  );
  assert.equal(result.primitives.length, 2);
  assert.equal(result.materials.length, 2);
  assert.equal(result.report.draws, 3);
  assert.deepEqual(result.nodes[2].primitives, [1]);
  near(result.nodes[2].world.slice(12), [1, 0, -1, 1]);
});

test("truncated, misordered and oversized GLB chunks reject", async () => {
  const valid = glb(original, binary(original));
  for (const [name, edit] of [
    ["truncated", (bytes) => bytes.subarray(0, -1)],
    [
      "wrong-version",
      (bytes) => {
        bytes.writeUInt32LE(1, 4);
        return bytes;
      },
    ],
    [
      "wrong-first-chunk",
      (bytes) => {
        bytes.writeUInt32LE(0x004e4942, 16);
        return bytes;
      },
    ],
    [
      "oversized-chunk",
      (bytes) => {
        bytes.writeUInt32LE(0x7ffffffc, 12);
        return bytes;
      },
    ],
  ]) {
    const file = resolve(root, name + ".glb");
    await writeFile(file, edit(Buffer.from(valid)));
    await assert.rejects(readGltf(file), /GLB/);
  }
});

test("vertex alpha, declared buffers, repeated draws and generated source enforce limits", async () => {
  await assert.rejects(
    readGltf(
      await fixture("vertex-alpha", (value) => {
        const bytes = binary(value);
        bytes[23] = 128;
        replaceBinary(value, bytes);
      }),
    ),
    /opaque alpha/,
  );
  await assert.rejects(
    readGltf(
      await fixture("buffer-limit", (value) => {
        value.buffers[0].byteLength = IMPORT_LIMITS.inputBytes + 1;
      }),
    ),
    /byteLength/,
  );
  await assert.rejects(
    readGltf(
      await fixture("draw-limit", (value) => {
        value.meshes[0].primitives = Array(3).fill(value.meshes[0].primitives[0]);
        for (let i = 2; i < 128; i++) {
          value.nodes.push({ name: `part-${i}`, mesh: 0 });
          value.nodes[0].children.push(i);
        }
      }),
    ),
    /draw budget/,
  );
  function whiteImage(size) {
    const row = [0, ...Array(size * 4).fill(255)];
    return png(size, size, Array.from({ length: size }, () => row).flat());
  }
  const oversizedSource = await fixture("source-limit", (value) => {
    value.images[0].uri = "data:image/png;base64," + whiteImage(128).toString("base64");
  });
  await assert.rejects(importModel(oversizedSource, resolve(root, "too-large")), /module exceeds/);
  const uploadLimit = await fixture("upload-limit", (value) => {
    value.images[0].uri = "data:image/png;base64," + whiteImage(256).toString("base64");
  });
  await assert.rejects(readGltf(uploadLimit), /upload byte budget/);
});

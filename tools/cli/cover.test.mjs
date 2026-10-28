import test from "node:test";
import assert from "node:assert/strict";
import { readFile, writeFile, mkdtemp, rm, link, mkdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { deflateSync } from "node:zlib";
import { chunks, chunk, signature, encodeCartridge } from "../sdk/cartridge.mjs";
import {
  composeCover,
  coverOptions,
  createCover,
  decodeCoverPng,
  extractWordmark,
} from "./cover.mjs";
import { metadataMask, moldMask } from "./cover-lettering.mjs";

const assets = {
  shell: await readFile(new URL("../../site/assets/brand/cartridge.png", import.meta.url)),
  logo: await readFile(new URL("../../site/assets/brand/logo.png", import.meta.url)),
};
const defaults = { language: "luau", display: "640x360" };

function fixture(width = 1, height = width, channels = 4, color = [255, 0, 0, 255], filter = 0) {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = channels === 4 ? 6 : 2;
  const stride = width * channels;
  const rows = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y++) {
    rows[y * (stride + 1)] = filter;
    for (let x = 0; x < stride; x++) {
      // A constant image has simple independent expected filter predictions.
      const value = color[x % channels];
      const left = x >= channels ? value : 0;
      const above = y ? value : 0;
      const prediction =
        [0, left, above, Math.floor((left + above) / 2), y ? above : left][filter] ?? 0;
      rows[y * (stride + 1) + x + 1] = (value - prediction + 256) % 256;
    }
  }
  return Buffer.concat([
    signature,
    chunk("IHDR", header),
    chunk("IDAT", deflateSync(rows)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

function pixel(image, x, y) {
  return [...image.pixels.subarray((y * image.width + x) * 4, (y * image.width + x) * 4 + 4)];
}

function replacePart(bytes, type, replacement) {
  return Buffer.concat([
    signature,
    ...chunks(bytes).map((part) => chunk(part.type, part.type === type ? replacement : part.data)),
  ]);
}

test("cover arguments validate options before any SDK or filesystem access", () => {
  assert.deepEqual(coverOptions(["art.png", "--output", "cover.png"]), {
    input: "art.png",
    output: "cover.png",
    ...defaults,
    force: false,
  });
  assert.equal(
    coverOptions([
      "--language",
      "odin",
      "art.png",
      "--output",
      "out.png",
      "--display",
      "320x180",
      "--force",
    ]).force,
    true,
  );
  for (const args of [
    [],
    ["a.png"],
    ["a.png", "b.png"],
    ["a.png", "--output"],
    ["a.png", "--output", "x.jpg"],
    ["a.png", "--output", "x.png", "--language", "lua"],
    ["a.png", "--output", "x.png", "--display", "800x600"],
    ["a.png", "--output", "x.png", "--force", "--force"],
    ["a.png", "--output", "x.png", "--unknown"],
  ]) {
    assert.throws(() => coverOptions(args), /Cartridge cover:/);
  }
});

test("PNG filters decode known RGB and RGBA values", () => {
  for (const channels of [3, 4]) {
    for (let filter = 0; filter <= 4; filter++) {
      const image = decodeCoverPng(fixture(3, 2, channels, [21, 143, 233, 127], filter));
      for (let y = 0; y < 2; y++) {
        for (let x = 0; x < 3; x++) {
          assert.deepEqual(pixel(image, x, y), [21, 143, 233, channels === 4 ? 127 : 255]);
        }
      }
    }
  }
});

test("fixed square placement, up/down scaling, transparency and deterministic bytes", () => {
  const small = composeCover(fixture(), assets, defaults);
  assert.deepEqual(small, composeCover(fixture(), assets, defaults));
  assert.deepEqual(small, composeCover(fixture(1024), assets, defaults));
  const image = decodeCoverPng(small);
  assert.equal(image.width, 839);
  assert.equal(image.height, 1024);
  assert.deepEqual(pixel(image, 148, 158), [255, 0, 0, 255]);
  assert.deepEqual(pixel(image, 701, 711), [255, 0, 0, 255]);
  assert.notDeepEqual(pixel(image, 147, 158), [255, 0, 0, 255]);
  assert.notDeepEqual(pixel(image, 702, 711), [255, 0, 0, 255]);
  assert.equal(pixel(image, 0, 0)[3], 0, "Shell exterior stays transparent");
  const opaqueAssets = { ...assets, shell: fixture(1, 1, 4, [20, 40, 60, 255]) };
  const transparent = decodeCoverPng(
    composeCover(fixture(1, 1, 4, [255, 0, 0, 0]), opaqueAssets, defaults),
  );
  const half = decodeCoverPng(
    composeCover(fixture(1, 1, 4, [255, 0, 0, 128]), opaqueAssets, defaults),
  );
  const background = pixel(transparent, 400, 400);
  assert.deepEqual(pixel(half, 400, 400), [
    Math.round((255 * 128) / 255 + (background[0] * 127) / 255),
    Math.round((background[1] * 127) / 255),
    Math.round((background[2] * 127) / 255),
    255,
  ]);
});

test("language and display only change top lettering, packing preserves all image bytes", () => {
  const luau = composeCover(fixture(), assets, defaults);
  const odin = composeCover(fixture(), assets, { language: "odin", display: "320x180" });
  const a = decodeCoverPng(luau),
    b = decodeCoverPng(odin);
  assert.deepEqual(a.pixels.subarray(145 * a.width * 4), b.pixels.subarray(145 * b.width * 4));
  assert.notDeepEqual(a.pixels, b.pixels);
  const packed = encodeCartridge({
    title: "Test",
    language: "luau",
    display: [640, 360],
    code: Buffer.from("return {}"),
    cover: luau,
  });
  assert.deepEqual(
    chunks(packed)
      .filter((part) => part.type !== "caRt")
      .map((part) => packed.subarray(part.offset, part.end)),
    chunks(luau).map((part) => luau.subarray(part.offset, part.end)),
  );
  assert.throws(() => composeCover(packed, assets, defaults), /packed cartridge/);
});

test("metadata uses smooth vector strokes and recessed markings have directional relief", () => {
  for (const text of ["LUAU / 640 x 360", "ODIN / 320 x 180"]) {
    const mask = metadataMask(text);
    const coverage = [];
    for (let at = 3; at < mask.pixels.length; at += 4) {
      coverage.push(mask.pixels[at]);
    }
    assert.ok(coverage.includes(255), "Letter strokes have solid interiors");
    assert.ok(
      coverage.some((value) => value > 0 && value < 255),
      "Edges are antialiased",
    );
    assert.ok(mask.width < 554 && mask.height < 30, "Metadata fits the top rail");
  }
  assert.throws(() => metadataMask("?"), /Unsupported cartridge lettering/);
  const mask = { width: 3, height: 3, pixels: Buffer.alloc(3 * 3 * 4, 255) };
  const calls = new Map();
  moldMask(null, mask, 0, 0, (_image, x, y, color) => calls.set(`${x},${y}`, color));
  assert.deepEqual(calls.get("0,0"), [25, 27, 30, 245], "Upper-left recess is shadowed");
  assert.deepEqual(calls.get("1,1"), [49, 51, 54, 245], "Interior stays plastic gray");
  assert.deepEqual(calls.get("3,3"), [130, 133, 139, 140], "Lower-right lip catches light");
});

test("molded logo retains white letter faces and excludes the red backing", () => {
  const source = decodeCoverPng(assets.logo);
  const mask = extractWordmark(assets.logo);
  let redPixels = 0,
    facePixels = 0;
  for (let y = 0; y < mask.height; y++) {
    for (let x = 0; x < mask.width; x++) {
      const color = pixel(source, x, y + 120);
      const coverage = mask.pixels[(y * mask.width + x) * 4 + 3];
      if (color[0] > 160 && color[1] < 60 && color[2] < 60) {
        assert.equal(coverage, 0, "Red extrusion cannot fill counters");
        redPixels++;
      } else if (Math.min(...color.slice(0, 3)) > 200) {
        assert.equal(coverage, color[3], "White letter faces retain their coverage");
        facePixels++;
      }
    }
  }
  assert.ok(redPixels > 5000 && facePixels > 5000, "Test covers both backing and letters");
});

test("malformed, excessive, unsupported and non-square images fail before composition", () => {
  assert.throws(() => composeCover(fixture(2, 1), assets, defaults), /square/);
  const png = fixture();
  const header = Buffer.from(chunks(png)[0].data);
  header.writeUInt32BE(4097);
  assert.throws(() => decodeCoverPng(replacePart(png, "IHDR", header)), /dimensions/);
  header.writeUInt32BE(1);
  header[12] = 1;
  assert.throws(() => decodeCoverPng(replacePart(png, "IHDR", header)), /noninterlaced/);
  assert.throws(() => decodeCoverPng(fixture(1, 1, 4, [0, 0, 0, 0], 5)), /filter/);
  assert.throws(() => decodeCoverPng(replacePart(png, "IDAT", deflateSync(Buffer.alloc(1000)))));
  const corrupt = Buffer.from(png);
  corrupt[30] ^= 1;
  assert.throws(() => decodeCoverPng(corrupt), /checksum/);
  assert.throws(() => decodeCoverPng(png.subarray(0, -1)), /chunk/);
  const animated = Buffer.concat([
    png.subarray(0, 33),
    chunk("acTL", Buffer.alloc(8)),
    png.subarray(33),
  ]);
  assert.throws(() => decodeCoverPng(animated), /animation/);
  const duplicate = Buffer.concat([
    png.subarray(0, 33),
    chunk("IHDR", chunks(png)[0].data),
    png.subarray(33),
  ]);
  assert.throws(() => decodeCoverPng(duplicate), /unsupported PNG chunk/);
});

test("output protection, force replacement and failed writes preserve authored files", async () => {
  const root = await mkdtemp(resolve(tmpdir(), "bytorio-cover-"));
  try {
    const input = resolve(root, "sticker.png"),
      output = resolve(root, "art/cover.png");
    await writeFile(input, fixture());
    const options = { ...defaults, input, output };
    await createCover(options, assets);
    const expected = await readFile(output);
    await assert.rejects(createCover(options, assets), /output exists/);
    await createCover({ ...options, force: true }, assets);
    assert.deepEqual(await readFile(output), expected);
    await assert.rejects(
      createCover({ ...options, output: input, force: true }, assets),
      /sticker/,
    );
    const alias = resolve(root, "alias.png");
    await link(input, alias);
    await assert.rejects(createCover({ ...options, output: alias, force: true }, assets), /alias/);
    const directory = resolve(root, "directory.png");
    await mkdir(directory);
    await assert.rejects(
      createCover({ ...options, output: directory, force: true }, assets),
      /directory/,
    );
    await writeFile(input, fixture(2, 1));
    await assert.rejects(createCover({ ...options, force: true }, assets), /square/);
    assert.deepEqual(await readFile(output), expected);
    await writeFile(input, fixture());
    const packed = encodeCartridge({
      title: "Test",
      language: "odin",
      display: [320, 180],
      code: Buffer.from([1]),
      cover: expected,
    });
    await writeFile(output, packed);
    await assert.rejects(createCover({ ...options, force: true }, assets), /packed cartridge/);
    assert.deepEqual(await readFile(output), packed);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

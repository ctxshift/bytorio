import assert from "node:assert/strict";
import { readFile, writeFile, mkdir, copyFile } from "node:fs/promises";
import { resolve } from "node:path";
import { randomUUID } from "node:crypto";
import { once } from "node:events";
import { timedSpawnSync as spawnSync } from "./command-timing.mjs";
import { createProject, buildProject } from "./sdk/project.mjs";
import { chunks, chunk, signature, encodeContent } from "./sdk/cartridge.mjs";
import { decodeCartridge, contentImports } from "../runtime/odin/web/cartridge.js";
import { chromium } from "./browser-timing.mjs";
import { serve } from "./serve.mjs";

const root = resolve("build/content-verification", randomUUID());
await mkdir(root, { recursive: true });
const asset = Buffer.alloc(3 * 1024 * 1024);
for (let i = 0; i < asset.length; i++) {
  asset[i] = i & 255;
}
const projects = {};
const images = {};
const reports = {};
function native(project, path, expected = 0) {
  const result = spawnSync(resolve(project, "build/native/player.exe"), [path, "--smoke"], {
    encoding: "utf8",
    timeout: 30000,
    env: {
      ...process.env,
      SDL_VIDEODRIVER: "dummy",
      SDL_AUDIODRIVER: "dummy",
      SDL_RENDER_DRIVER: "software",
    },
  });
  assert.ifError(result.error);
  assert.equal(result.status, expected, result.stderr + result.stdout);
  return result;
}
for (const language of ["odin", "luau"]) {
  const project = resolve(root, language);
  projects[language] = project;
  await createProject(project, language);
  await copyFile(`tests/content/game.${language}`, resolve(project, `src/main.${language}`));
  await writeFile(resolve(project, "large.bin"), asset);
  await writeFile(resolve(project, "small.bin"), Buffer.from([17, 23, 41, 89]));
  const manifest = JSON.parse(await readFile(resolve(project, "console.json"), "utf8"));
  manifest.content = [
    { id: 0xffffffff, path: "small.bin" },
    { id: 7, path: "large.bin" },
  ];
  await writeFile(resolve(project, "console.json"), JSON.stringify(manifest));
  await buildProject(project);
  const path = resolve(project, "build/game.png");
  images[language] = await readFile(path);
  reports[language] = JSON.parse(native(project, path).stdout);
}
const runtime = (
  await WebAssembly.instantiate(await readFile(resolve(projects.odin, "build/web/runtime.wasm")), {
    env: { sin: Math.sin },
  })
).instance.exports;
decodeCartridge(runtime, images.odin);
const memory = new WebAssembly.Memory({ initial: 17, maximum: 128 });
const access = contentImports(runtime, () => ({ memory }));
const destination = new Uint8Array(memory.buffer, 128, 4);
destination.fill(91);
assert.equal(access.content_size(7), asset.length);
assert.equal(access.content_read(7, 1023, 128, 4), 1);
assert.deepEqual([...destination], [255, 0, 1, 2]);
for (const args of [
  [7, asset.length - 3, 128, 4],
  [7, 0xffffffff, 128, 4],
  [7, 0, 0xffffffff, 4],
  [7, 0, 0, 1048577],
  [9, 0, 128, 4],
]) {
  assert.equal(access.content_read(...args), 0);
  assert.deepEqual([...destination], [255, 0, 1, 2]);
}
assert.equal(access.content_read(7, asset.length, 128, 0), 1);
assert.equal(access.content_size(9), 0);
for (const input of [new Uint8Array(0), new Uint8Array(runtime.runtime_cartridge_capacity() + 1)]) {
  decodeCartridge(runtime, images.odin);
  assert.throws(() => decodeCartridge(runtime, input), /size/);
  assert.equal(access.content_size(7), 0, "invalid outer size clears previous content");
  assert.equal(access.content_read(7, 0, 128, 4), 0);
  assert.deepEqual([...destination], [255, 0, 1, 2]);
}
const parts = chunks(images.odin);
const content = parts.find(({ type }) => type === "coNt").data;
function malformedContent(edit) {
  const bytes = Buffer.from(content);
  edit(bytes);
  return Buffer.concat([
    signature,
    ...parts.map((part) => chunk(part.type, part.type === "coNt" ? bytes : part.data)),
  ]);
}
const malformed = [
  ["version", (b) => b.writeUInt32LE(2, 4)],
  ["empty-index", (b) => b.writeUInt32LE(0, 8)],
  ["index-overflow", (b) => b.writeUInt32LE(0xffffffff, 8)],
  ["zero-id", (b) => b.writeUInt32LE(0, 12)],
  ["duplicate-id", (b) => b.writeUInt32LE(7, 24)],
  ["overlap", (b) => b.writeUInt32LE(0, 28)],
  ["gap", (b) => b.writeUInt32LE(1, 16)],
  ["overflow", (b) => b.writeUInt32LE(0xffffffff, 20)],
  ["empty-entry", (b) => b.writeUInt32LE(0, 20)],
  ["trailing-data", (b) => b.writeUInt32LE(3, 32)],
];
for (const [name, edit] of malformed) {
  const png = malformedContent(edit);
  assert.throws(() => decodeCartridge(runtime, png), /content/);
  assert.equal(runtime.runtime_content_size(7), 0, "failed parse cannot publish previous content");
  const path = resolve(root, `${name}.png`);
  await writeFile(path, png);
  assert.match(native(projects.odin, path, 1).stderr, /content/);
}
for (const entries of [
  [{ id: 0, bytes: asset }],
  [{ id: 1, bytes: Buffer.alloc(0) }],
  [
    { id: 7, bytes: asset },
    { id: 7, bytes: asset },
  ],
]) {
  assert.throws(() => encodeContent(entries));
}
const stripped = Buffer.concat([
  signature,
  ...parts.filter((part) => part.type !== "coNt").map((part) => chunk(part.type, part.data)),
]);
decodeCartridge(runtime, images.odin);
decodeCartridge(runtime, stripped);
assert.equal(
  runtime.runtime_content_size(7),
  0,
  "reloading a content-free cartridge clears the index",
);

const server = serve(root, 0);
await once(server, "listening");
const browser = await chromium.launch({
  channel: process.env.PLAYER_BROWSER_CHANNEL || "chrome",
  headless: true,
});
try {
  const page = await browser.newPage();
  for (const language of ["odin", "luau"]) {
    await page.goto(
      `http://127.0.0.1:${server.address().port}/${language}/build/web/player.html?game=./game.png&smoke`,
    );
    await page.waitForFunction(() => playerStatus.ready || playerStatus.error);
    assert.equal(await page.evaluate(() => playerStatus.error), "");
    await page.locator("#start").click();
    await page.waitForFunction(() => playerStatus.ticks >= 120 || playerStatus.error);
    assert.equal(await page.evaluate(() => playerStatus.error), "");
    assert.equal(await page.evaluate(() => playerStatus.hash), reports[language].hash);
  }
} finally {
  await browser.close();
  await new Promise((done) => server.close(done));
}
console.log(
  `Indexed content passed: exact bytes and bounded reads through both SDKs/native/browser, ${malformed.length} malformed indexes, failed-parse rollback and reload clearing.`,
);

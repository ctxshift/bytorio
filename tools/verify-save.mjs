import assert from "node:assert/strict";
import { copyFile, mkdir, readFile, writeFile, readdir, chmod } from "node:fs/promises";
import { resolve } from "node:path";
import { createHash, randomUUID } from "node:crypto";
import { once } from "node:events";
import { timedSpawnSync as spawnSync } from "./command-timing.mjs";
import { createProject, buildProject } from "./sdk/project.mjs";
import { chromium } from "./browser-timing.mjs";
import { serve } from "./serve.mjs";

const root = resolve("build/save-verification", randomUUID());
await mkdir(root, { recursive: true });
const expected = Buffer.from(Array.from({ length: 65536 }, (_, i) => (i * 37 + 11) % 256));
const projects = {};
const savedKeys = [];
for (const language of ["odin", "luau"]) {
  const project = resolve(root, language);
  projects[language] = project;
  await createProject(project, language);
  await copyFile(`tests/save/game.${language}`, resolve(project, `src/main.${language}`));
  await buildProject(project);
  const cartridge = resolve(project, "build/game.png");
  const saveDirectory = resolve(root, "saves");
  const key = createHash("sha256")
    .update(await readFile(cartridge))
    .digest("hex");
  const saved = resolve(saveDirectory, `${key}.sav`);
  savedKeys.push(`${key}.sav`);
  const replay = resolve(project, "inputs.txt");
  async function native(masks, expectedExit = 0) {
    await writeFile(replay, masks.join("\n"));
    const result = spawnSync(
      resolve(project, "build/native/player.exe"),
      [cartridge, "--replay", replay],
      {
        encoding: "utf8",
        timeout: 30000,
        env: { ...process.env, BYTORIO_SAVE_DIRECTORY: saveDirectory },
      },
    );
    assert.ifError(result.error);
    assert.equal(result.status, expectedExit, result.stderr + result.stdout);
    return result.status === 0 ? result.stdout.trim().split(/\r?\n/).map(JSON.parse) : [];
  }
  const first = await native([16, 0, 2, 0, 1]);
  assert.deepEqual(
    first.map((frame) => frame.sounds),
    [0, 0, 1, 1, 2],
  );
  assert.deepEqual(
    await readFile(saved),
    expected,
    "maximum-size write owns original staging bytes",
  );
  await chmod(saved, 0o444);
  try {
    await native([4], 1);
    assert.deepEqual(await readFile(saved), expected, "failed atomic replace retains prior save");
  } finally {
    await chmod(saved, 0o666);
  }
  await native([8, 0, 2]);
  assert.deepEqual(await readFile(saved), expected.subarray(0, 4096));
  assert.equal((await native([0]))[0].sounds, 1, "legacy-size record remains readable");
  const replaced = await native([4, 0, 2]);
  assert.deepEqual(
    replaced.map((frame) => frame.sounds),
    [1, 1, 2],
  );
  assert.deepEqual(await readFile(saved), Buffer.from([7, 8, 9]));
  assert.equal((await native([0]))[0].sounds, 1, "fresh process reads stored bytes");
  assert.deepEqual(
    (await readdir(saveDirectory)).sort(),
    [...savedKeys].sort(),
    "temporary file cleaned after success and failure",
  );
  await writeFile(saved, Buffer.alloc(65537));
  assert.equal((await native([0]))[0].sounds, 0, "oversized disk record rejected before reading");
}

const server = serve(root, 0);
await once(server, "listening");
const browser = await chromium.launch({
  channel: process.env.PLAYER_BROWSER_CHANNEL || "chrome",
  headless: true,
});
try {
  const page = await browser.newPage();
  for (const language of ["odin", "luau"]) {
    await page.goto(`http://127.0.0.1:${server.address().port}/${language}/build/web/player.html`);
    await page.waitForFunction(() => playerStatus.ready || playerStatus.error);
    assert.equal(await page.evaluate(() => playerStatus.error), "");
    const report = await page.evaluate(async () => {
      async function session() {
        const worker = new Worker("./worker.js", { type: "module" });
        const request = (message) =>
          new Promise((resolve, reject) => {
            const timeout = setTimeout(() => {
              worker.terminate();
              reject(new Error("save worker deadline"));
            }, 15000);
            worker.onmessage = async ({ data }) => {
              if (data.type === "executing") {
                return;
              }
              if (data.type === "executor") {
                try {
                  const bytes = await (await fetch("./luau-executor.wasm")).arrayBuffer();
                  worker.postMessage({ type: "executor", executor: { bytes } });
                } catch (error) {
                  clearTimeout(timeout);
                  reject(error);
                }
                return;
              }
              clearTimeout(timeout);
              if (data.type === "error") {
                reject(new Error(data.error));
              } else {
                resolve(data);
              }
            };
            worker.onerror = (error) => {
              clearTimeout(timeout);
              reject(error);
            };
            worker.postMessage(message);
          });
        await request({ type: "load", gameUrl: "./game.png" });
        const step = (buttons = 0) =>
          request({
            type: "step",
            steps: 1,
            render: true,
            input: { buttons, pointer: false, x: 0, y: 0 },
          });
        const committed = async (frame) => {
          for (let i = 0; i < 100 && frame.y === 2; i++) {
            frame = await step();
          }
          if (frame.y !== 1) {
            throw new Error(`save did not commit: ${frame.y}`);
          }
          return frame;
        };
        return { worker, step, committed };
      }
      let game = await session();
      let frame = await game.step();
      if (frame.x !== 0 || frame.y !== 0) {
        throw new Error("new cartridge must start empty");
      }
      frame = await game.committed(await game.step(16));
      if (frame.x * 16 !== 65536) {
        throw new Error("maximum save length missing");
      }
      await game.step();
      frame = await game.step(2);
      if (frame.sounds !== 1) {
        throw new Error("saved bytes differ from expected pattern");
      }
      await game.step();
      frame = await game.step(1);
      if (frame.sounds !== 2) {
        throw new Error("bounds checks failed");
      }
      game.worker.terminate();
      game = await session();
      frame = await game.step();
      if (frame.x * 16 !== 65536 || frame.y !== 1 || frame.sounds !== 1) {
        throw new Error("restart lost committed save");
      }
      await game.committed(await game.step(8));
      game.worker.terminate();
      game = await session();
      frame = await game.step();
      if (frame.x * 16 !== 4096 || frame.y !== 1 || frame.sounds !== 1) {
        throw new Error("legacy-size record did not remain readable");
      }
      await game.committed(await game.step(4));
      game.worker.terminate();
      game = await session();
      frame = await game.step();
      if (frame.x * 16 !== 3 || frame.y !== 1 || frame.sounds !== 1) {
        throw new Error("replacement did not persist");
      }
      game.worker.terminate();
      return { length: frame.x * 16, state: frame.y, sounds: frame.sounds };
    });
    assert.deepEqual(report, { length: 3, state: 1, sounds: 1 });
  }
} finally {
  await browser.close();
  await new Promise((done) => server.close(done));
}
console.log(
  "Save conformance passed: both SDKs/native/browser, 64 KiB snapshots, legacy-size restart, cartridge isolation, atomic replacement, rollback and bounds.",
);

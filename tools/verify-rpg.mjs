import assert from "node:assert/strict";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
import { once } from "node:events";
import { chromium } from "playwright";
import { serve } from "./serve.mjs";
import { uploadGraphics, submitDrawing, rasterizeDrawing } from "../runtime/odin/web/policy.js";

const out = "build/rpg/verification";
await mkdir(out, { recursive: true });
const imports = { env: { sin: Math.sin } };
const gameBytes = await readFile("build/rpg-odin/web/game.wasm");
const runtimeBytes = await readFile("build/rpg-odin/web/runtime.wasm");
const smokeReports = {};
for (const [language, executable] of [
  ["luau", "build/rpg-luau/native/Release/player.exe"],
  ["odin", "build/rpg-odin/native/player.exe"],
]) {
  const result = spawnSync(
    resolve(executable),
    ["--smoke", "--capture", `${out}/${language}-native.bmp`],
    {
      encoding: "utf8",
      timeout: 30000,
      env: {
        ...process.env,
        SDL_VIDEODRIVER: "dummy",
        SDL_AUDIODRIVER: "dummy",
        SDL_RENDER_DRIVER: "software",
      },
    },
  );
  if (result.error) {
    throw result.error;
  }
  assert.equal(result.status, 0, `${language} native SDL smoke: ${result.stderr}`);
  smokeReports[language] = JSON.parse(result.stdout);
  assert.equal(smokeReports[language].ticks, 120);
}
for (const name of ["list-count", "list-offset", "list-command"]) {
  const result = spawnSync(
    resolve("build/rpg-odin/native/player.exe"),
    ["--check", "--game", `build/rpg-odin/web/fixtures/${name}.wasm`],
    { encoding: "utf8", timeout: 10000 },
  );
  if (result.error) {
    throw result.error;
  }
  assert.equal(result.status, 1, `${name} rejected by native player`);
  assert.match(result.stderr, /display list|invalid frame command/i);
}
assert.deepEqual(gameBytes, await readFile("build/rpg-odin/native/game.wasm"));
async function cartridge() {
  const game = (await WebAssembly.instantiate(gameBytes, imports)).instance.exports;
  const runtime = (await WebAssembly.instantiate(runtimeBytes, imports)).instance.exports;
  game.game_init();
  runtime.runtime_init();
  uploadGraphics(game, runtime);
  function state() {
    return Array.from(new Int32Array(game.memory.buffer, game.game_inspect(), 10));
  }
  function step(mask) {
    game.game_update(mask, 0, 0, 0);
    const drawing = submitDrawing(game, runtime);
    rasterizeDrawing(runtime, drawing);
    return { hash: runtime.runtime_hash() >>> 0, sounds: drawing.record.sounds };
  }
  return { state, step };
}
const cases = [];
async function scenario(name, run) {
  const cart = await cartridge(),
    masks = [],
    frames = [],
    checkpoints = [];
  const step = (mask) => {
    masks.push(mask);
    frames.push(cart.step(mask));
  };
  const tap = (mask) => {
    step(mask);
    step(0);
  };
  const walk = (mask, n = 1) => {
    for (let i = 0; i < n; i++) {
      tap(mask);
    }
  };
  const check = (label, expected) => {
    const actual = cart.state();
    for (const [index, value] of Object.entries(expected)) {
      assert.equal(actual[index], value, `${name}: ${label} field ${index}`);
    }
    checkpoints.push({ label, tick: masks.length, state: actual, hash: frames.at(-1)?.hash });
  };
  run({ step, tap, walk, check });
  const file = resolve(out, `${name}.inputs`);
  await writeFile(file, masks.join("\n") + "\n");
  for (const [host, exe, args] of [
    ["Luau native", "build/rpg-luau/native/Release/rpg_replay.exe", ["build/rpg/main.luau", file]],
    ["Odin native", "build/rpg-odin/native/player.exe", ["--replay", file]],
  ]) {
    const result = spawnSync(resolve(exe), args, {
      encoding: "utf8",
      timeout: 60000,
      maxBuffer: 2 * 1024 * 1024,
    });
    if (result.error) {
      throw result.error;
    }
    assert.equal(result.status, 0, `${host}: ${result.stderr}`);
    const actual = result.stdout
      .trim()
      .split(/\r?\n/)
      .map((line) => JSON.parse(line));
    assert.equal(actual.length, frames.length, `${host} replay length`);
    for (let tick = 0; tick < frames.length; tick++) {
      assert.deepEqual(actual[tick], frames[tick], `${host} ${name} tick ${tick + 1}`);
    }
  }
  cases.push({ name, masks, frames, checkpoints });
  console.log(`${name}: ${masks.length} identical frames on Node Wasm and both native players.`);
}
await scenario("quest", ({ step, tap, walk, check }) => {
  walk(4);
  walk(4);
  check("NPC blocks walking", { 0: 5, 1: 5 });
  step(16);
  for (let i = 0; i < 12; i++) {
    step(16);
  }
  check("held action stays in dialogue", { 6: 1, 7: 1 });
  step(0);
  tap(16);
  check("accept quest", { 6: 0, 7: 1 });
  walk(8);
  walk(2, 9);
  walk(4);
  walk(2);
  check("river collision", { 0: 14, 1: 5 });
  walk(8);
  walk(2, 5);
  check("bridge and encounter", { 0: 19, 1: 6, 6: 2, 4: 10 });
  tap(16);
  check("attack", { 2: 17, 4: 6 });
  tap(2);
  tap(16);
  check("guard", { 2: 16, 4: 6, 5: 1 });
  tap(2);
  tap(16);
  check("potion", { 2: 17, 3: 0, 4: 6 });
  tap(16);
  check("empty potion consumes no turn", { 2: 17, 3: 0, 4: 6 });
  tap(1);
  tap(1);
  tap(16);
  tap(16);
  check("victory", { 2: 14, 6: 1, 7: 5 });
  tap(16);
  walk(2, 4);
  tap(16);
  check("collect sunleaf", { 0: 23, 1: 6, 6: 1, 7: 7 });
  tap(16);
  walk(1, 18);
  walk(4);
  tap(16);
  check("quest complete", { 0: 5, 1: 5, 2: 20, 6: 1, 7: 15 });
  tap(16);
  tap(16);
  check("repeat NPC dialogue", { 6: 1, 7: 15 });
});
await scenario("defeat", ({ tap, walk, check }) => {
  walk(2, 14);
  check("encounter without quest", { 6: 2, 7: 0 });
  tap(2);
  for (let i = 0; i < 20; i++) {
    tap(16);
  }
  check("defeat", { 2: 0, 6: 1, 7: 16 });
  tap(16);
  check("recover at village", { 0: 5, 1: 6, 2: 20, 3: 1, 4: 10, 6: 0, 7: 0 });
  walk(4);
  tap(16);
  check("quest still available", { 6: 1, 7: 1 });
});

const servers = [
  serve("build/rpg-odin/web", 0),
  serve("build/rpg-luau/web", 0),
  serve("build/rpg/site", 0),
];
await Promise.all(servers.map((server) => once(server, "listening")));
let browser;
try {
  browser = await chromium.launch({ channel: process.env.PLAYER_BROWSER_CHANNEL || undefined });
  const page = await browser.newPage({ viewport: { width: 1200, height: 820 } });
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  const odinUrl = `http://127.0.0.1:${servers[0].address().port}/player.html`;
  await page.goto(odinUrl);
  await page.waitForFunction(
    () => globalThis.playerStatus?.ready || globalThis.playerStatus?.error,
  );
  assert.equal(await page.evaluate(() => playerStatus.error), "");
  await page.getByRole("button", { name: "Start game" }).click();
  await page.keyboard.down("ArrowUp");
  await page.waitForFunction(() => playerStatus.y === 5);
  await page.keyboard.up("ArrowUp");
  await page.keyboard.press("Space", { delay: 100 });
  await page.waitForFunction(() => playerStatus.sounds >= 2);
  await page.screenshot({ path: `${out}/odin-dialog.png` });
  assert.ok(await page.evaluate(() => playerAudio.played >= 2 && playerAudio.peak > 0.1));
  for (const name of ["list-count", "list-offset", "list-command"]) {
    await page.goto(`${odinUrl}?game=fixtures/${name}.wasm`);
    await page.waitForFunction(() => !!playerStatus.error);
    assert.match(await page.evaluate(() => playerStatus.error), /display list/i);
  }
  await page.goto(odinUrl);
  await page.waitForFunction(() => playerStatus.ready);
  for (const test of cases) {
    const frames = await page.evaluate(async (masks) => {
      const worker = new Worker("./worker.js", { type: "module" });
      try {
        const exchange = (data) =>
          new Promise((resolve, reject) => {
            const timer = setTimeout(() => reject(new Error("RPG Worker timeout")), 10000);
            worker.onmessage = ({ data }) => {
              if (data.type === "executing") {
                return;
              }
              clearTimeout(timer);
              if (data.type === "error") {
                reject(new Error(data.error));
              } else {
                resolve(data);
              }
            };
            worker.postMessage(data);
          });
        await exchange({ type: "load", gameUrl: "./game.wasm" });
        const frames = [];
        for (const mask of masks) {
          const frame = await exchange({
            type: "step",
            steps: 1,
            input: { buttons: mask, pointer: false, x: 0, y: 0 },
          });
          frames.push({ hash: frame.hash, sounds: frame.sounds });
        }
        return frames;
      } finally {
        worker.terminate();
      }
    }, test.masks);
    assert.equal(frames.length, test.frames.length);
    for (let tick = 0; tick < frames.length; tick++) {
      assert.deepEqual(
        frames[tick],
        test.frames[tick],
        `Odin browser ${test.name} tick ${tick + 1}`,
      );
    }
  }
  const luauUrl = `http://127.0.0.1:${servers[1].address().port}/player.html`;
  for (const test of cases) {
    await page.goto(`${luauUrl}?replay`);
    await page.waitForFunction(
      () => playerStatus?.ready && !document.getElementById("start").disabled,
    );
    await page.getByRole("button", { name: "Start game" }).click();
    const frames = await page.evaluate(
      (masks) =>
        masks.map((mask) => {
          Module._player_step(mask);
          if (playerStatus.error) {
            throw new Error(playerStatus.error);
          }
          return { hash: playerStatus.hash, sounds: playerStatus.sounds };
        }),
      test.masks,
    );
    assert.equal(frames.length, test.frames.length);
    for (let tick = 0; tick < frames.length; tick++) {
      assert.deepEqual(
        frames[tick],
        test.frames[tick],
        `Luau browser ${test.name} tick ${tick + 1}`,
      );
    }
    if (test.name === "quest") {
      await page.evaluate(
        () => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))),
      );
      await page.screenshot({ path: `${out}/luau-complete.png` });
      await page.goto(`${luauUrl}?replay`);
      await page.waitForFunction(
        () => playerStatus?.ready && !document.getElementById("start").disabled,
      );
      const encounter = test.checkpoints.find(
        (checkpoint) => checkpoint.label === "bridge and encounter",
      ).tick;
      await page.evaluate(
        (masks) => {
          for (const mask of masks) {
            Module._player_step(mask);
          }
        },
        test.masks.slice(0, encounter),
      );
      await page.evaluate(
        () => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))),
      );
      await page.screenshot({ path: `${out}/luau-battle.png` });
    }
  }
  await page.goto(luauUrl);
  await page.waitForFunction(
    () => playerStatus?.ready && !document.getElementById("start").disabled,
  );
  await page.getByRole("button", { name: "Start game" }).click();
  await page.keyboard.down("ArrowRight");
  await page.waitForFunction(() => playerStatus.ticks > 20);
  await page.keyboard.up("ArrowRight");
  await page.keyboard.press("Space", { delay: 100 });
  await page.waitForFunction(() => playerAudio.played >= 2);
  assert.ok(await page.evaluate(() => playerAudio.peak > 0.1));
  const launcher = `http://127.0.0.1:${servers[2].address().port}`;
  await page.goto(`${launcher}/player.html`);
  assert.equal(await page.getByRole("link", { name: /Play Luau/ }).count(), 1);
  assert.equal(await page.getByRole("link", { name: /Play Odin/ }).count(), 1);
  for (const language of ["odin", "luau"]) {
    console.log(`Checking ${language} launcher controls.`);
    await page.goto(`${launcher}/${language}/player.html`);
    await page.waitForFunction(
      () => playerStatus?.ready && !document.getElementById("start").disabled,
    );
    const initial = await page.evaluate(() => playerStatus.hash);
    await page.getByRole("button", { name: "Start game" }).click();
    await page.getByRole("button", { name: "Move Up", exact: true }).scrollIntoViewIfNeeded();
    const up = await page.getByRole("button", { name: "Move Up", exact: true }).boundingBox();
    await page.mouse.move(up.x + up.width / 2, up.y + up.height / 2);
    await page.mouse.down();
    try {
      await page.waitForFunction((hash) => playerStatus.hash !== hash, initial, { timeout: 5000 });
    } catch (error) {
      console.error(
        await page.evaluate(() => ({ status: playerStatus, active: document.activeElement?.id })),
      );
      throw error;
    }
    await page.mouse.up();
    const action = await page
      .getByRole("button", { name: "Talk or confirm", exact: true })
      .boundingBox();
    await page.mouse.move(action.x + action.width / 2, action.y + action.height / 2);
    await page.mouse.down();
    await page.waitForFunction(() => playerStatus.sounds >= 2);
    await page.mouse.up();
    assert.ok(await page.evaluate(() => playerAudio.played >= 2));
  }
  assert.deepEqual(errors, []);
  const report = {
    browser: browser.version(),
    nativeSmoke: smokeReports,
    cases: cases.map(({ name, masks, checkpoints }) => ({
      name,
      ticks: masks.length,
      checkpoints,
    })),
    hosts: ["Luau native", "Odin native", "Luau browser", "Odin browser", "Node Wasm"],
  };
  await writeFile(`${out}/report.json`, JSON.stringify(report, null, 2) + "\n");
  console.log(
    `RPG checks passed on all five execution paths (${cases.reduce((n, c) => n + c.masks.length, 0)} frames per path).`,
  );
} finally {
  await browser?.close();
  await Promise.all(servers.map((server) => new Promise((resolve) => server.close(resolve))));
}

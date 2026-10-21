import assert from "node:assert/strict";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
import { once } from "node:events";
import { chromium } from "../../../tools/browser-timing.mjs";
import { serve } from "../../../tools/serve.mjs";
import {
  loadSource,
  checkExecutor,
  uploadGraphics,
  submitDrawing,
  rasterizeDrawing,
} from "../../../runtime/odin/web/policy.js";
export const root = "examples/racing/build/player";
export const out = `${root}/verification`;
await mkdir(out, { recursive: true });
for (const file of ["game.wasm", "luau-executor.wasm", "racing.luau"]) {
  assert.deepEqual(
    await readFile(`${root}/web/${file}`),
    await readFile(`${root}/native/${file}`),
    "identical cartridge/executor bytes on both hosts",
  );
}
const imports = {
  env: {
    sin: Math.sin,
    content_size: () => 0,
    content_read: () => 0,
    save_size: () => 0,
    save_status: () => 3,
    save_read: () => 0,
    save_write: () => 3,
  },
};
export async function instance(language) {
  const game = (
    await WebAssembly.instantiate(
      await readFile(`${root}/web/${language === "odin" ? "game" : "luau-executor"}.wasm`),
      imports,
    )
  ).instance.exports;
  const runtime = (
    await WebAssembly.instantiate(await readFile(`${root}/web/runtime.wasm`), imports)
  ).instance.exports;
  game._initialize?.();
  if (language === "luau") {
    loadSource(game, await readFile(`${root}/web/racing.luau`));
  }
  game.game_init();
  checkExecutor(game);
  runtime.runtime_init();
  uploadGraphics(game, runtime);
  return { game, runtime };
}
export function step(pair, mask) {
  pair.game.game_update(mask, 0, 0, 0);
  const drawing = submitDrawing(pair.game, pair.runtime);
  rasterizeDrawing(pair.runtime, drawing);
  assert.equal(drawing.width, 320);
  assert.equal(drawing.height, 180);
  return { hash: pair.runtime.runtime_hash() >>> 0, sounds: drawing.record.sounds };
}
const reference = await instance("odin");
const state = () =>
  Array.from(new Int32Array(reference.game.memory.buffer, reference.game.game_inspect(), 10));
export const race = [];
export const expected = [];
let finished;
let topSpeed = 0;
for (let tick = 0; tick < 3000; tick++) {
  const s = state();
  let mask = 4;
  if (s[1] < -360) {
    mask |= 2;
  } else if (s[1] > -340) {
    mask |= 1;
  }
  if (tick % 300 < 45) {
    mask |= 16;
  }
  race.push(mask);
  expected.push(step(reference, mask));
  topSpeed = Math.max(topSpeed, state()[2]);
  if (state()[8]) {
    finished = state();
    break;
  }
}
assert.ok(finished, "autodriver finishes three laps within 50 seconds");
assert.ok(finished[0] >= 216000);
assert.ok(finished[7] > 0, "boost used");
assert.ok(finished[5] > 0, "kart collisions exercised");
assert.ok(topSpeed > 180, "boost exceeds normal top speed");
race.push(0, 16);
expected.push(step(reference, 0), step(reference, 16));
assert.equal(state()[0], 0, "restart resets distance");
for (let i = 0; i < 150; i++) {
  race.push(4);
  expected.push(step(reference, 4));
}
export const handling = [
  ...Array(90).fill(0),
  ...Array(100).fill(4),
  ...Array(100).fill(6),
  ...Array(60).fill(8),
  ...Array(130).fill(5),
  ...Array(150).fill(20),
];
reference.game.game_init();
export const handlingExpected = handling.map((mask, i) => {
  const frame = step(reference, mask);
  if (i === 349) {
    assert.equal(state()[2], 0, "braking stops the kart");
  }
  return frame;
});
assert.ok(state()[6] > 0, "off-road slowdown exercised");
assert.ok(state()[2] > 0, "recovered speed");
const golden = JSON.parse(await readFile("tests/sdk/racing-parity.json", "utf8"));
assert.deepEqual(expected, golden.race, "SDK migration preserves the race and restart");
assert.deepEqual(handlingExpected, golden.handling, "SDK migration preserves handling");
for (const [name, inputs] of [
  ["race", race],
  ["handling", handling],
]) {
  await writeFile(`${out}/${name}.inputs`, inputs.join("\n") + "\n");
}
for (const language of ["odin", "luau"]) {
  const pair = await instance(language);
  for (const [name, inputs, frames] of [
    ["race", race, expected],
    ["handling", handling, handlingExpected],
  ]) {
    pair.game.game_init();
    for (let i = 0; i < inputs.length; i++) {
      assert.deepEqual(step(pair, inputs[i]), frames[i], `${language} ${name} frame ${i}`);
    }
    const args = [
      "--game",
      `${root}/native/${language === "odin" ? "game" : "luau-executor"}.wasm`,
      "--replay",
      `${out}/${name}.inputs`,
    ];
    if (language === "luau") {
      args.push("--source", `${root}/native/racing.luau`);
    }
    const result = spawnSync(resolve(`${root}/native/player.exe`), args, {
      encoding: "utf8",
      timeout: 60000,
      maxBuffer: 2 * 1024 * 1024,
    });
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(
      result.stdout.trim().split(/\r?\n/).map(JSON.parse),
      frames,
      `${language} native ${name}`,
    );
  }
  const smoke = spawnSync(
    resolve(`${root}/native/player.exe`),
    [
      "--game",
      `${root}/native/${language === "odin" ? "game" : "luau-executor"}.wasm`,
      ...(language === "luau" ? ["--source", `${root}/native/racing.luau`] : []),
      "--smoke",
      "--capture",
      `${out}/${language}-native.bmp`,
    ],
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
  assert.equal(smoke.status, 0, smoke.stderr);
  const report = JSON.parse(smoke.stdout);
  assert.equal(report.ticks, 120);
  assert.ok(report.audioQueuedFrames > 0);
}
console.log(
  `Node/native parity passed: ${race.length} race frames, ${handling.length} handling frames per language. Finish: ${finished[4]} ticks; collisions ${finished[5]}.`,
);
const server = serve(`${root}/web`, 0);
await once(server, "listening");
const browser = await chromium.launch({
  channel: process.env.PLAYER_BROWSER_CHANNEL || "chrome",
  headless: true,
});
try {
  const page = await browser.newPage({ viewport: { width: 1100, height: 900 } });
  for (const language of ["odin", "luau"]) {
    await page.goto(
      `http://127.0.0.1:${server.address().port}/player.html${language === "luau" ? "?game=./racing.luau" : ""}`,
    );
    await page.waitForFunction(() => playerStatus.ready || playerStatus.error);
    assert.equal(await page.evaluate(() => playerStatus.error), "");
    assert.deepEqual(await page.locator("canvas").evaluate((c) => [c.width, c.height]), [320, 180]);
    const traces = await page.evaluate(
      async ({ race, handling, language }) => {
        const worker = new Worker("./worker.js", { type: "module" });
        const next = () =>
          new Promise((resolve, reject) => {
            const deadline = setTimeout(() => reject(new Error("Worker deadline")), 30000);
            worker.onmessage = ({ data }) => {
              if (data.type === "executing") {
                return;
              }
              clearTimeout(deadline);
              if (data.type === "error") {
                reject(new Error(data.error));
              } else {
                resolve(data);
              }
            };
            worker.onerror = reject;
          });
        let pending = next();
        worker.postMessage({
          type: "load",
          gameUrl: language === "luau" ? "./racing.luau" : "./game.wasm",
        });
        await pending;
        const result = [];
        for (const masks of [race, handling]) {
          pending = next();
          worker.postMessage({ type: "benchmark", masks });
          result.push((await pending).traces);
        }
        worker.terminate();
        return result;
      },
      { race, handling, language },
    );
    assert.deepEqual(traces, [expected, handlingExpected], `${language} browser parity`);
    await page.locator("#start").click();
    await page.keyboard.down("ArrowUp");
    await page.waitForFunction(() => playerStatus.ticks >= 240);
    await page.evaluate(() => window.dispatchEvent(new Event("blur")));
    await page.waitForTimeout(100);
    await page.keyboard.up("ArrowUp");
    const live = await page.evaluate(() => playerStatus),
      driven = await instance("odin");
    let drivenFrame;
    for (let tick = 0; tick < live.ticks; tick++) {
      drivenFrame = step(driven, 4);
    }
    assert.equal(live.hash, drivenFrame.hash, "keyboard acceleration matches held-gas replay");
    assert.ok((await page.evaluate(() => playerAudio.played)) > 0, "gesture-unlocked audio");
    await page.locator("canvas").screenshot({ path: `${out}/${language}-browser.png` });
  }
} finally {
  await browser.close();
  await new Promise((r) => server.close(r));
}
await writeFile(
  `${out}/parity.json`,
  JSON.stringify(
    {
      raceFrames: race.length,
      handlingFrames: handling.length,
      finish: finished,
      passed: ["node", "native", "browser", "native-sdl", "browser-keyboard", "browser-audio"],
    },
    null,
    2,
  ) + "\n",
);
console.log(
  "Browser parity, active resolution, live keyboard and audio passed for both cartridges.",
);

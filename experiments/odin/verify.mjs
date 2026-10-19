import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFile, mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { chromium } from "playwright";

// Run from the repository root. Keep this probe independent of the current player.
const compiler = process.argv[2] ? resolve(process.argv[2]) : "odin";
await mkdir("build/odin", { recursive: true });

function run(program, args) {
  const result = spawnSync(program, args, { encoding: "utf8", timeout: 30000 });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    throw new Error(`${result.stdout}\n${result.stderr}`);
  }
  return result.stdout.trim();
}

const versionOutput = run(compiler, ["version"]);
const version = versionOutput.includes(" version ")
  ? versionOutput.split(" version ").at(-1)
  : versionOutput;
const timings = { wasm: [], native: [] };
for (let attempt = 0; attempt < 3; attempt++) {
  for (const target of ["wasm", "native"]) {
    const args = [
      "build",
      "experiments/odin",
      "-o:minimal",
      `-out:build/odin/game.${target === "wasm" ? "wasm" : "exe"}`,
    ];
    if (target === "wasm") {
      args.push("-target:freestanding_wasm32", "-no-entry-point");
    }
    const start = performance.now();
    run(compiler, args);
    timings[target].push(Math.round(performance.now() - start));
  }
}

const nativeOutput = run(resolve("build/odin/game.exe"), []);
const native = Object.fromEntries(
  nativeOutput.split(/\s+/).map((pair) => {
    const [name, value] = pair.split("=");
    return [name, Number(value)];
  }),
);
const bytes = await readFile("build/odin/game.wasm");
const module = new WebAssembly.Module(bytes);
const imports = WebAssembly.Module.imports(module);
assert.deepEqual(imports, [], "freestanding probe does not require browser/OS imports");
const exports = WebAssembly.Module.exports(module).map((item) => item.name);

function exercise(instance) {
  const game = instance.exports;
  game.game_init();
  for (let tick = 0; tick < 120; tick++) {
    game.game_update(1 / 60, tick < 60 ? 2 : tick === 60 ? 16 : 0);
  }
  const state = {
    x: game.game_x(),
    y: game.game_y(),
    ticks: game.game_ticks(),
    sounds: game.game_sounds(),
  };
  assert.ok(Math.abs(state.x - 284) < 1e-8);
  assert.equal(state.y, 100);
  assert.equal(state.ticks, 120);
  assert.equal(state.sounds, 2);
  assert.equal(game.probe_bounds(0), 11);
  assert.throws(() => game.probe_bounds(4), WebAssembly.RuntimeError);
  return { state, linearMemoryBytes: game.memory.buffer.byteLength, boundsTrap: true };
}

const node = exercise(new WebAssembly.Instance(module, {}));
assert.ok(Math.abs(native.x - node.state.x) < 1e-8);
assert.equal(native.y, node.state.y);
assert.equal(native.ticks, node.state.ticks);
assert.equal(native.sounds, node.state.sounds);
const browser = await chromium.launch({ channel: process.env.PLAYER_BROWSER_CHANNEL || undefined });
let chrome;
try {
  const page = await browser.newPage();
  chrome = await page.evaluate(
    async (data) => {
      const { instance } = await WebAssembly.instantiate(new Uint8Array(data), {});
      const game = instance.exports;
      game.game_init();
      for (let tick = 0; tick < 120; tick++) {
        game.game_update(1 / 60, tick < 60 ? 2 : tick === 60 ? 16 : 0);
      }
      let boundsTrap = false;
      try {
        game.probe_bounds(4);
      } catch (error) {
        boundsTrap = error instanceof WebAssembly.RuntimeError;
      }
      return {
        state: {
          x: game.game_x(),
          y: game.game_y(),
          ticks: game.game_ticks(),
          sounds: game.game_sounds(),
        },
        linearMemoryBytes: game.memory.buffer.byteLength,
        boundsTrap,
      };
    },
    [...bytes],
  );
  assert.deepEqual(chrome.state, node.state);
  assert.equal(chrome.boundsTrap, true);
  chrome.browserVersion = browser.version();
} finally {
  await browser.close();
}

const report = {
  compiler: version,
  optimization: "minimal",
  timingsMs: timings,
  wasmBytes: bytes.length,
  imports,
  exports,
  native,
  node,
  chrome,
  limitations: [
    "No C++ Wasm engine integration",
    "No actual rendering or audio playback",
    "No allocator/heap-budget test",
    "No runaway-loop metering test",
    "No realistic workload, cold-cache or comparative performance benchmark",
  ],
};
await writeFile("build/odin/report.json", JSON.stringify(report, null, 2) + "\n");
console.log(JSON.stringify(report));

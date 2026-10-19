import { resourceSchema as limits } from "../runtime/odin/web/constants.js";
import { mkdir, copyFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { parseArgs } from "node:util";
import { tool, dependencyRoot, run, script, repo } from "./toolchain.mjs";

const { values } = parseArgs({
  options: {
    target: { type: "string", default: "all" },
    game: { type: "string", default: "hello" },
    fixtures: { type: "boolean", default: false },
  },
});
const { target, game, fixtures } = values;
if (!["all", "native", "web"].includes(target) || !["hello", "rpg", "racing"].includes(game)) {
  throw new Error("Invalid build target or game");
}
const odin = tool("odin");
if (!run(odin, ["version"]).includes("84bc3fc")) {
  throw new Error("Odin dev-2026-10 (84bc3fc) is required");
}
const prefix = game === "hello" ? "odin-player" : `${game}-odin`;
const web = `build/${prefix}/web`,
  native = `build/${prefix}/native`;
const source = `examples/${game}-odin`;
if (game !== "hello") {
  script(`tools/build-${game}-assets.mjs`);
}
await mkdir(web, { recursive: true });
await mkdir(native, { recursive: true });
const common = [
  game === "hello" ? "-o:minimal" : "-o:speed",
  "-source-code-locations:filename",
  `-collection:sdk=${resolve(repo, "sdk/odin")}`,
];
const build = (args) => run(odin, ["build", ...args], { stdio: "inherit" });
const wasm = ["-target:freestanding_wasm32", "-no-entry-point", ...common];
// The shared real-time mixer needs production optimization even for a small guest.
const hostFlags = common.map((flag) => (flag.startsWith("-o:") ? "-o:speed" : flag));
const hostWasm = ["-target:freestanding_wasm32", "-no-entry-point", ...hostFlags];
build([source, ...wasm, `-out:${web}/game.wasm`, "-extra-linker-flags:--max-memory=8388608"]);
const compilerRoot = dirname(odin);
if (target !== "native") {
  build([
    "runtime/odin/web",
    ...hostWasm,
    `-out:${web}/runtime.wasm`,
    `-extra-linker-flags:--max-memory=${limits.maxRuntimeBytes}`,
  ]);
  build([
    "runtime/odin/audio_web",
    ...hostWasm,
    `-out:${web}/audio.wasm`,
    `-extra-linker-flags:--max-memory=${limits.maxAudioRuntimeBytes}`,
  ]);
  for (const file of [
    "player.html",
    "player.js",
    "worker.js",
    "policy.js",
    "audio-worklet.js",
    "constants.js",
    "cartridge.js",
    "executor-cache.js",
    "executor-cache-core.js",
  ]) {
    await copyFile(`runtime/odin/web/${file}`, `${web}/${file}`);
  }
  await mkdir(`${web}/licenses`, { recursive: true });
  await copyFile(resolve(compilerRoot, "LICENSE"), `${web}/licenses/odin.txt`);
}
if (target !== "web") {
  if (process.platform !== "win32") {
    throw new Error("The native adapter currently targets Windows x64");
  }
  const dependency = dependencyRoot();
  build([
    "runtime/odin/native",
    ...hostFlags,
    `-out:${native}/player.exe`,
    `-collection:deps=${dependency}`,
  ]);
  await copyFile(`${web}/game.wasm`, `${native}/game.wasm`);
  await copyFile(resolve(dependency, "wasmtime.dll"), `${native}/wasmtime.dll`);
  await copyFile(resolve(compilerRoot, "vendor/sdl3/SDL3.dll"), `${native}/SDL3.dll`);
  await mkdir(`${native}/licenses`, { recursive: true });
  for (const [from, name] of [
    [resolve(dependency, "../LICENSE"), "wasmtime"],
    [resolve(compilerRoot, "vendor/sdl3/LICENSE.txt"), "sdl3"],
    [resolve(compilerRoot, "LICENSE"), "odin"],
  ]) {
    await copyFile(from, `${native}/licenses/${name}.txt`);
  }
}
if (fixtures) {
  await mkdir(`${web}/fixtures`, { recursive: true });
  const kinds = [
    "loop",
    "abi",
    "offset",
    "command",
    "trap",
    "list-count",
    "list-offset",
    "list-command",
  ];
  for (const [index, kind] of kinds.entries()) {
    build([
      "tests/odin/fixtures",
      ...wasm,
      `-define:TEST_FAULT=${index + 1}`,
      `-out:${web}/fixtures/${kind}.wasm`,
      "-extra-linker-flags:--max-memory=8388608",
    ]);
  }
}
console.log(`Odin ${game} ${target} build ready in ${web} and ${native}.`);

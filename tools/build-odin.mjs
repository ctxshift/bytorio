import { resourceSchema as limits } from "../runtime/odin/web/constants.js";
import { mkdir, copyFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { parseArgs } from "node:util";
import { exportPlayer, stagePlayerSupport } from "./player-export.mjs";
import { tool, dependencyRoot, run, script, repo, task } from "./toolchain.mjs";

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
// Game cartridges differ, but all use the same optimized native/browser host.
const reusePlayer = game !== "hello" && target === "all";
if (reusePlayer) {
  task("build:odin");
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
  if (reusePlayer) {
    await exportPlayer({ platform: "web", source: "build/odin-player/web", target: web });
  } else {
    build([
      "runtime/odin/web",
      ...hostWasm,
      `-out:${web}/runtime.wasm`,
      `-extra-linker-flags:--max-memory=${limits.maxRuntimeBytes}`,
    ]);
    build([
      "runtime/odin/web",
      ...hostWasm,
      "-define:GPU_RASTER=true",
      `-out:${web}/runtime-gpu.wasm`,
      `-extra-linker-flags:--max-memory=${limits.maxRuntimeBytes}`,
    ]);
    build([
      "runtime/odin/audio_web",
      ...hostWasm,
      `-out:${web}/audio.wasm`,
      `-extra-linker-flags:--max-memory=${limits.maxAudioRuntimeBytes}`,
    ]);
  }
  if (!reusePlayer) {
    await stagePlayerSupport({ platform: "web", target: web, compilerRoot });
  }
}
if (target !== "web") {
  if (process.platform !== "win32") {
    throw new Error("The native adapter currently targets Windows x64");
  }
  const dependency = dependencyRoot();
  if (reusePlayer) {
    await exportPlayer({ platform: "native", source: "build/odin-player/native", target: native });
  } else {
    build([
      "runtime/odin/native",
      ...hostFlags,
      `-out:${native}/player.exe`,
      `-collection:deps=${dependency}`,
    ]);
  }
  await copyFile(`${web}/game.wasm`, `${native}/game.wasm`);
  if (!reusePlayer) {
    await stagePlayerSupport({ platform: "native", target: native, compilerRoot, dependency });
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

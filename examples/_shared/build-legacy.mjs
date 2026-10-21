import { mkdir, copyFile } from "node:fs/promises";
import { resolve } from "node:path";
import { parseArgs } from "node:util";
import { exportPlayer } from "../../tools/player-export.mjs";
import { tool, run, script, repo, task } from "../../tools/toolchain.mjs";

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

async function main() {
  // The dependency tasks own the shared player, even for single-host exports.
  task(target === "all" ? "build:odin" : `deps:player:${target}`);
  if (game === "hello") {
    if (fixtures && target !== "all") {
      task("deps:player:fixtures");
    }
    return;
  }

  const odin = tool("odin");
  const web = `examples/${game}/build/odin/web`;
  const native = `examples/${game}/build/odin/native`;
  const source = `examples/${game}/odin`;
  script(`examples/${game}/tools/assets.mjs`);
  await mkdir(web, { recursive: true });
  await mkdir(native, { recursive: true });
  const wasm = [
    "-target:freestanding_wasm32",
    "-no-entry-point",
    "-o:speed",
    "-source-code-locations:filename",
    `-collection:sdk=${resolve(repo, "sdk/odin")}`,
  ];
  const build = (args) => run(odin, ["build", ...args], { stdio: "inherit" });
  build([source, ...wasm, `-out:${web}/game.wasm`, "-extra-linker-flags:--max-memory=8388608"]);
  if (target !== "native") {
    await exportPlayer({ platform: "web", source: "build/odin-player/web", target: web });
  }
  if (target !== "web") {
    await exportPlayer({ platform: "native", source: "build/odin-player/native", target: native });
    await copyFile(`${web}/game.wasm`, `${native}/game.wasm`);
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
}

await main();

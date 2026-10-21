import { copyFile, mkdir } from "node:fs/promises";
import { resolve } from "node:path";
import { exportPlayer } from "../../../tools/player-export.mjs";
import { task } from "../../../tools/toolchain.mjs";

task("build:odin");
for (const platform of ["native", "web"]) {
  const source = resolve("build/odin-player", platform);
  const target = resolve("examples/hello/build", platform);
  await mkdir(target, { recursive: true });
  await exportPlayer({ platform, source, target });
  await copyFile(resolve(source, "game.wasm"), resolve(target, "game.wasm"));
}

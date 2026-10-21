import { dirname, resolve } from "node:path";
import { stagePlayerSupport } from "./player-export.mjs";
import { dependencyRoot, repo, tool } from "./toolchain.mjs";

const platform = process.argv[2];
if (!["web", "native"].includes(platform)) {
  throw new Error("Specify web or native player support");
}
await stagePlayerSupport({
  platform,
  target: resolve(repo, "build/odin-player", platform),
  compilerRoot: dirname(tool("odin")),
  dependency: platform === "native" ? dependencyRoot() : undefined,
});

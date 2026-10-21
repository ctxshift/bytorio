import { copyFile, mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { resourceSchema as limits } from "../runtime/odin/web/constants.js";
import { dependencyRoot, repo, run, tool } from "./toolchain.mjs";

const artifact = process.argv[2];
const web = resolve(repo, "build/odin-player/web");
const native = resolve(repo, "build/odin-player/native");
const odin = tool("odin");
const common = [
  "-o:speed",
  "-source-code-locations:filename",
  `-collection:sdk=${resolve(repo, "sdk/odin")}`,
];
const wasm = ["-target:freestanding_wasm32", "-no-entry-point", ...common];
const guest = [
  "-target:freestanding_wasm32",
  "-no-entry-point",
  "-o:minimal",
  "-source-code-locations:filename",
  `-collection:sdk=${resolve(repo, "sdk/odin")}`,
];

if (!run(odin, ["version"]).includes("84bc3fc")) {
  throw new Error("Odin dev-2026-10 (84bc3fc) is required");
}

async function build(source, flags, output) {
  await mkdir(dirname(output), { recursive: true });
  run(odin, ["build", source, ...flags, `-out:${output}`], { stdio: "inherit" });
}

switch (artifact) {
  case "web-cpu":
  case "web-gpu":
    await build(
      "runtime/odin/web",
      [
        ...wasm,
        ...(artifact === "web-gpu" ? ["-define:GPU_RASTER=true"] : []),
        `-extra-linker-flags:--max-memory=${limits.maxRuntimeBytes}`,
      ],
      resolve(web, artifact === "web-gpu" ? "runtime-gpu.wasm" : "runtime.wasm"),
    );
    break;
  case "web-audio":
    await build(
      "runtime/odin/audio_web",
      [...wasm, `-extra-linker-flags:--max-memory=${limits.maxAudioRuntimeBytes}`],
      resolve(web, "audio.wasm"),
    );
    break;
  case "native":
    if (process.platform !== "win32") {
      throw new Error("The native adapter currently targets Windows x64");
    }
    await build(
      "runtime/odin/native",
      [...common, `-collection:deps=${dependencyRoot()}`],
      resolve(native, "player.exe"),
    );
    break;
  case "hello":
    await build(
      "examples/hello-odin",
      [...guest, "-extra-linker-flags:--max-memory=8388608"],
      resolve(web, "game.wasm"),
    );
    await mkdir(native, { recursive: true });
    await copyFile(resolve(web, "game.wasm"), resolve(native, "game.wasm"));
    break;
  case "fixtures": {
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
      await build(
        "tests/odin/fixtures",
        [...guest, `-define:TEST_FAULT=${index + 1}`, "-extra-linker-flags:--max-memory=8388608"],
        resolve(web, "fixtures", `${kind}.wasm`),
      );
    }
    break;
  }
  default:
    throw new Error(`Unknown player artifact: ${artifact}`);
}

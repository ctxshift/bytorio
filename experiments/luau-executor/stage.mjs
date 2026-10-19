import { readFile, writeFile, copyFile, mkdir, readdir } from "node:fs/promises";
import { createHash } from "node:crypto";
const root = process.argv[2] || "build/unified-player";
const racing = process.argv[3] === "racing";
const cartridge = racing ? "racing" : "rpg";
for (const platform of ["web", "native"]) {
  const target = `${root}/${platform}`,
    source = `build/${cartridge}-odin/${platform}`;
  await mkdir(`${target}/licenses`, { recursive: true });
  const files =
    platform === "web"
      ? [
          "player.html",
          "player.js",
          "policy.js",
          "worker.js",
          "executor-cache.js",
          "executor-cache-core.js",
          "runtime.wasm",
          "game.wasm",
        ]
      : ["player.exe", "SDL3.dll", "wasmtime.dll", "game.wasm"];
  for (const file of files) {
    await copyFile(`${source}/${file}`, `${target}/${file}`);
  }
  await copyFile("build/luau-executor/luau-executor.wasm", `${target}/luau-executor.wasm`);
  await copyFile(
    racing ? "build/racing/racing.luau" : "build/rpg/batched.luau",
    `${target}/${cartridge}.luau`,
  );
  for (const file of await readdir(`${source}/licenses`)) {
    await copyFile(`${source}/licenses/${file}`, `${target}/licenses/${file}`);
  }
  await copyFile(".tools/emsdk/upstream/emscripten/LICENSE", `${target}/licenses/emscripten.txt`);
  for (const [path, name] of [
    ["libcxx/LICENSE.TXT", "libcxx.txt"],
    ["libcxxabi/LICENSE.TXT", "libcxxabi.txt"],
    ["libc/musl/COPYRIGHT", "musl.txt"],
  ]) {
    await copyFile(
      `.tools/emsdk/upstream/emscripten/system/lib/${path}`,
      `${target}/licenses/${name}`,
    );
  }
  await copyFile(
    "build/luau-executor/_deps/luau-src/LICENSE.txt",
    `${target}/licenses/luau.txt`,
  ).catch(async (error) => {
    if (error.code !== "ENOENT") {
      throw error;
    }
    await copyFile("build/native/_deps/luau-src/LICENSE.txt", `${target}/licenses/luau.txt`);
  });
}
const html = await readFile(`${root}/web/player.html`, "utf8");
const executor = await readFile(`${root}/web/luau-executor.wasm`);
await writeFile(
  `${root}/web/executor-version.json`,
  JSON.stringify({ sha256: createHash("sha256").update(executor).digest("hex") }) + "\n",
);
await writeFile(
  `${root}/web/player.html`,
  html.replace("</body>", '<script type="module" src="./controls.js"></script>\n</body>'),
);
const controls = await readFile(`examples/${racing ? "racing" : "rpg"}-shared/controls.js`, "utf8");
const stagedControls = controls.replace(
  /back\.href\s*=\s*["']\.\.\/player\.html["']/,
  'back.href = "./comparison.html"',
);
if (!racing && stagedControls === controls) {
  throw new Error("Could not configure the comparison link in game controls.");
}
await writeFile(`${root}/web/controls.js`, stagedControls);
const launcher = await readFile(
  `examples/${racing ? "racing" : "rpg"}-shared/launcher.html`,
  "utf8",
);
await writeFile(
  `${root}/web/comparison.html`,
  launcher
    .replace("./luau/player.html", "./player.html?game=./rpg.luau")
    .replace("./odin/player.html", "./player.html")
    .replace("Luau game · C++ player", "Luau game · Wasm executor · Odin player")
    .replace("Odin game · Odin player", "Odin game · Wasm cartridge · Odin player"),
);
console.log(`Unified prototype staged in ${root}.`);

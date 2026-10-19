import { readFile, writeFile, mkdir, readdir, copyFile, stat, realpath } from "node:fs/promises";
import { resolve, dirname, relative, sep } from "node:path";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";
import { Worker } from "node:worker_threads";
import { readGraphics } from "./assets.mjs";
import { bundleLuau, odinEntry } from "./bundle.mjs";
import { inspectGuest } from "../../runtime/odin/web/policy.js";

export const repo = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const contract = JSON.parse(await readFile(resolve(repo, "sdk/contract.json"), "utf8"));
export function command(exe, args, options = {}) {
  const result = spawnSync(exe, args, { cwd: repo, stdio: "inherit", timeout: 600000, ...options });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    throw new Error(`${exe.split(/[\\/]/).at(-1)} failed (${result.status})`);
  }
  return result;
}
const ps = (file) => command("pwsh", ["-NoProfile", "-File", resolve(repo, "tools", file)]);
const exists = async (path) => {
  try {
    await stat(path);
    return true;
  } catch (error) {
    if (error.code === "ENOENT") {
      return false;
    }
    throw error;
  }
};
export async function files(root, extensions) {
  const found = [];
  async function visit(dir) {
    for (const entry of (await readdir(dir, { withFileTypes: true })).sort((a, b) =>
      a.name.localeCompare(b.name),
    )) {
      if (["build", "node_modules", ".git", ".console"].includes(entry.name)) {
        continue;
      }
      const path = resolve(dir, entry.name);
      if (entry.isSymbolicLink()) {
        throw new Error("Project source symlinks are not supported");
      }
      if (entry.isDirectory()) {
        await visit(path);
      } else if (extensions.some((ext) => entry.name.endsWith(ext))) {
        found.push(path);
      }
    }
  }
  await visit(root);
  return found;
}
async function inside(project, path) {
  if (
    typeof path !== "string" ||
    !path ||
    path.includes("\\") ||
    path.startsWith("/") ||
    /^[A-Za-z]:/.test(path)
  ) {
    throw new Error("Project paths must be relative and use forward slashes");
  }
  const result = await realpath(resolve(project, path));
  if (result !== project && !result.startsWith(project + sep)) {
    throw new Error("Project path escapes its directory");
  }
  return result;
}
export async function manifest(path) {
  const project = await realpath(resolve(path));
  const value = JSON.parse(await readFile(resolve(project, "console.json"), "utf8"));
  if (value.sdk !== contract.sdkVersion) {
    throw new Error(`This tool requires SDK ${contract.sdkVersion}`);
  }
  if (!["odin", "luau"].includes(value.language)) {
    throw new Error("language must be luau or odin");
  }
  if (
    !contract.displayModes.some(
      ([w, h]) =>
        value.display?.[0] === w && value.display?.[1] === h && value.display.length === 2,
    )
  ) {
    throw new Error("Unsupported display mode");
  }
  return {
    ...value,
    project,
    entry: await inside(project, value.entry),
    assets: await inside(project, value.assets),
  };
}
export async function syncEditor(project) {
  const target = resolve(project, ".console");
  await mkdir(target, { recursive: true });
  for (const file of ["console.luau", "native.luau"]) {
    await copyFile(resolve(repo, "sdk/luau", file), resolve(target, file));
  }
}
export async function createProject(path, language = "luau") {
  if (!["luau", "odin"].includes(language)) {
    throw new Error("language must be luau or odin");
  }
  const project = resolve(path);
  // Exclusive creation preserves existing folders and user files.
  await mkdir(project);
  await mkdir(resolve(project, "src"));
  await writeFile(
    resolve(project, "console.json"),
    JSON.stringify(
      {
        sdk: contract.sdkVersion,
        title: "Hello, Console!",
        language,
        entry: language === "luau" ? "src/main.luau" : "src",
        assets: "assets.json",
        display: [640, 360],
      },
      null,
      2,
    ) + "\n",
  );
  await writeFile(resolve(project, ".gitignore"), "build/\n.console/\n");
  await writeFile(
    resolve(project, ".luaurc"),
    JSON.stringify(
      { languageMode: "strict", aliases: { console: "./.console/console" } },
      null,
      2,
    ) + "\n",
  );
  await copyFile(
    resolve(repo, `sdk/templates/main.${language === "luau" ? "luau" : "odin"}`),
    resolve(project, `src/main.${language === "luau" ? "luau" : "odin"}`),
  );
  const shared = JSON.parse(
    await readFile(resolve(repo, "examples/rpg-shared/assets.json"), "utf8"),
  );
  await writeFile(
    resolve(project, "assets.json"),
    JSON.stringify(
      { palette: shared.palette, sprites: [shared.sprites[6]], font: shared.font },
      null,
      2,
    ) + "\n",
  );
  await syncEditor(project);
  console.log(`Created ${language} project: ${path}`);
  return project;
}
async function odinCompiler() {
  const exe = resolve(repo, ".tools/odin/dist/odin.exe");
  if (!(await exists(exe))) {
    ps("build-odin.ps1");
  }
  const version = spawnSync(exe, ["version"], { encoding: "utf8" });
  if (!version.stdout?.includes("84bc3fc")) {
    throw new Error("Odin dev-2026-10 (84bc3fc) is required");
  }
  return exe;
}
async function analyzer() {
  const exe = resolve(repo, ".tools/luau-tools/Release/luau-analyze.exe");
  if (!(await exists(exe))) {
    ps("build-luau-tools.ps1");
  }
  return exe;
}
async function prepare(path) {
  const spec = await manifest(path);
  const { packet, palette } = await readGraphics(spec.assets);
  const generated = resolve(spec.project, "build/generated");
  await mkdir(generated, { recursive: true });
  if (spec.language === "luau") {
    await syncEditor(spec.project);
    const sources = await files(spec.project, [".luau"]);
    command(await analyzer(), sources, { cwd: spec.project });
    const source = await bundleLuau({
      entry: spec.entry,
      project: spec.project,
      sdkRoot: resolve(repo, "sdk/luau"),
      assets: packet,
      display: spec.display,
    });
    await writeFile(resolve(generated, "game.luau"), source);
  } else {
    const sources = await files(spec.entry, [".odin"]);
    if (sources.length === 0) {
      throw new Error("No Odin sources found");
    }
    const list = new Set(sources.map((file) => relative(spec.entry, file).replaceAll("\\", "/")));
    if (
      list.has("console_entry.odin") ||
      [...list].some((name) => name.startsWith("console_assets/"))
    ) {
      throw new Error("Source uses a reserved SDK filename");
    }
    // Remove only stale compiler inputs previously generated inside this project's build folder.
    const { rm } = await import("node:fs/promises");
    const destination = resolve(generated, "odin");
    if (!destination.startsWith(resolve(spec.project, "build") + sep)) {
      throw new Error("Invalid generated source directory");
    }
    await rm(destination, { recursive: true, force: true });
    await mkdir(destination, { recursive: true });
    for (const file of sources) {
      const target = resolve(destination, relative(spec.entry, file));
      await mkdir(dirname(target), { recursive: true });
      await copyFile(file, target);
    }
    await mkdir(resolve(destination, "console_assets"));
    await writeFile(
      resolve(destination, "console_assets/assets.odin"),
      `package assets\nraster := [${packet.length}]u8{${[...packet]}}\npalette := [16]u32{${palette}}\n`,
    );
    await writeFile(
      resolve(destination, "console_entry.odin"),
      odinEntry({
        graphicsImport: 'assets "./console_assets"',
        display: spec.display[0] === 320 ? "Low" : "High",
      }),
    );
    const exe = await odinCompiler();
    command(exe, [
      "build",
      destination,
      "-target:freestanding_wasm32",
      "-no-entry-point",
      "-o:speed",
      "-source-code-locations:filename",
      `-collection:sdk=${resolve(repo, "sdk/odin")}`,
      `-out:${resolve(generated, "game.wasm")}`,
      "-extra-linker-flags:--max-memory=8388608",
    ]);
    const bytes = await readFile(resolve(generated, "game.wasm"));
    inspectGuest(bytes);
    const module = new WebAssembly.Module(bytes);
    for (const name of Object.keys(contract.requiredExports)) {
      if (
        !WebAssembly.Module.exports(module).some(
          (item) => item.name === name && item.kind === "function",
        )
      ) {
        throw new Error(`Missing SDK export: ${name}`);
      }
    }
  }
  return { ...spec, generated };
}
async function player() {
  const sources = [
    ...(await files(resolve(repo, "runtime/odin"), [".odin", ".js", ".html"])),
    resolve(repo, "tools/build-odin.ps1"),
  ];
  await cachedBuild(
    "sdk-player-hash",
    sources,
    [
      "build/odin-player/native/player.exe",
      "build/odin-player/native/SDL3.dll",
      "build/odin-player/native/wasmtime.dll",
      "build/odin-player/web/runtime.wasm",
    ],
    "build-odin.ps1",
  );
}
async function executor() {
  const sources = [
    ...(await files(resolve(repo, "experiments/luau-executor"), [".cpp", "CMakeLists.txt"])),
    resolve(repo, "tools/build-luau-executor.ps1"),
  ];
  await cachedBuild(
    "sdk-executor-hash",
    sources,
    ["build/luau-executor/luau-executor.wasm", "build/luau-executor/_deps/luau-src/LICENSE.txt"],
    "build-luau-executor.ps1",
  );
}
async function cachedBuild(name, sources, required, script) {
  const hash = createHash("sha256");
  for (const file of sources) {
    hash.update(relative(repo, file)).update(await readFile(file));
  }
  const key = hash.digest("hex"),
    stamp = resolve(repo, "build", name);
  if (
    !(await exists(stamp)) ||
    (await readFile(stamp, "utf8")) !== key ||
    !(await Promise.all(required.map((file) => exists(resolve(repo, file))))).every(Boolean)
  ) {
    ps(script);
    await writeFile(stamp, key);
  }
}
async function smoke(spec) {
  const luau = spec.language === "luau";
  await new Promise((done, reject) => {
    const worker = new Worker(new URL("./smoke-worker.mjs", import.meta.url), {
      workerData: {
        game: luau
          ? resolve(repo, "build/luau-executor/luau-executor.wasm")
          : resolve(spec.generated, "game.wasm"),
        source: luau ? resolve(spec.generated, "game.luau") : null,
        runtime: resolve(repo, "build/odin-player/web/runtime.wasm"),
      },
    });
    let settled = false,
      timer;
    const finish = (error) => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      worker.terminate();
      if (error) {
        reject(error);
      } else {
        done();
      }
    };
    timer = setTimeout(() => finish(new Error("SDK check timed out while loading")), 10000);
    worker.on("message", (message) => {
      if (message.type === "executing") {
        clearTimeout(timer);
        timer = setTimeout(
          () => finish(new Error("Game stopped responding during SDK check")),
          1000,
        );
      } else {
        finish(message.type === "error" ? new Error(message.message) : null);
      }
    });
    worker.on("error", finish);
    worker.on("exit", (code) => {
      if (!settled) {
        finish(new Error(`SDK check worker exited (${code})`));
      }
    });
  });
}
export async function checkProject(path) {
  const spec = await prepare(path);
  await player();
  if (spec.language === "luau") {
    await executor();
  }
  await smoke(spec);
  console.log(
    `Checked ${spec.language} SDK ${contract.sdkVersion}: types, assets, ABI and first frames.`,
  );
  return spec;
}
export async function buildProject(path) {
  const spec = await checkProject(path),
    luau = spec.language === "luau";
  for (const platform of ["web", "native"]) {
    const target = resolve(spec.project, "build", platform),
      base = resolve(repo, "build/odin-player", platform);
    await mkdir(resolve(target, "licenses"), { recursive: true });
    const names =
      platform === "web"
        ? [
            "player.html",
            "player.js",
            "worker.js",
            "policy.js",
            "executor-cache.js",
            "executor-cache-core.js",
            "runtime.wasm",
          ]
        : ["player.exe", "SDL3.dll", "wasmtime.dll"];
    for (const file of names) {
      await copyFile(resolve(base, file), resolve(target, file));
    }
    const { cp } = await import("node:fs/promises");
    await cp(resolve(base, "licenses"), resolve(target, "licenses"), { recursive: true });
    await copyFile(
      resolve(spec.generated, luau ? "game.luau" : "game.wasm"),
      resolve(target, luau ? "game.luau" : "game.wasm"),
    );
    if (luau) {
      const executor = await readFile(resolve(repo, "build/luau-executor/luau-executor.wasm"));
      await writeFile(resolve(target, "luau-executor.wasm"), executor);
      await writeFile(
        resolve(target, "executor-version.json"),
        JSON.stringify({ sha256: createHash("sha256").update(executor).digest("hex") }) + "\n",
      );
      for (const [source, name] of [
        ["build/luau-executor/_deps/luau-src/LICENSE.txt", "luau.txt"],
        [".tools/emsdk/upstream/emscripten/LICENSE", "emscripten.txt"],
        [".tools/emsdk/upstream/emscripten/system/lib/libcxx/LICENSE.TXT", "libcxx.txt"],
        [".tools/emsdk/upstream/emscripten/system/lib/libcxxabi/LICENSE.TXT", "libcxxabi.txt"],
        [".tools/emsdk/upstream/emscripten/system/lib/libc/musl/COPYRIGHT", "musl.txt"],
      ]) {
        await copyFile(resolve(repo, source), resolve(target, "licenses", name));
      }
    }
    await writeFile(
      resolve(target, "console.json"),
      JSON.stringify(
        {
          sdk: spec.sdk,
          language: spec.language,
          title: spec.title || "Console game",
          display: spec.display,
        },
        null,
        2,
      ) + "\n",
    );
    if (platform === "web") {
      const html = await readFile(resolve(target, "player.html"), "utf8");
      const title = String(spec.title || "Console game")
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;");
      await writeFile(
        resolve(target, "player.html"),
        html
          .replace(/<title>.*?<\/title>/, `<title>${title}</title>`)
          .replace(
            '<script type="module"',
            `<script>globalThis.playerCartridge=${JSON.stringify(luau ? "./game.luau" : "./game.wasm")}</script>\n<script type="module"`,
          ),
      );
    }
  }
  console.log(`Built ${spec.language}: ${relative(process.cwd(), resolve(spec.project, "build"))}`);
  return spec;
}

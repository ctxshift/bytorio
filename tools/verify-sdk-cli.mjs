import assert from "node:assert/strict";
import { readFile, writeFile, mkdir, unlink } from "node:fs/promises";
import { resolve } from "node:path";
import { randomUUID } from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import { createServer } from "node:net";
import { once } from "node:events";
import { bundleLuau } from "./sdk/bundle.mjs";
const root = resolve("build/sdk-cli-verification", randomUUID());
await mkdir(root, { recursive: true });
const project = resolve(root, "game");
function cli(args, status = 0) {
  const result = spawnSync(process.execPath, ["tools/console.mjs", ...args], {
    encoding: "utf8",
    timeout: 30000,
  });
  assert.equal(result.status, status, result.stdout + "\n" + result.stderr);
  return result;
}
cli(["new", project]);
assert.match(cli(["run", project, "--fps", "241"], 1).stderr, /Frame rate/);
const editorSettings = JSON.parse(await readFile(".vscode/settings.json", "utf8"));
assert.equal(editorSettings["luau-lsp.fflags.enableNewSolver"], true);
assert.equal(editorSettings["luau-lsp.platform.type"], "standard");
assert.deepEqual(
  JSON.parse(await readFile(resolve(project, ".vscode/settings.json"), "utf8")),
  editorSettings,
  "new Luau projects align editor analysis with the SDK analyzer",
);
const main = resolve(project, "src/main.luau"),
  original = await readFile(main, "utf8");
cli(["new", project], 1);
assert.equal(await readFile(main, "utf8"), original, "new preserves existing projects");
const manifest = JSON.parse(await readFile(resolve(project, "console.json"), "utf8"));
manifest.display = [320, 180];
await writeFile(resolve(project, "console.json"), JSON.stringify(manifest));
await writeFile(
  resolve(project, "src/message.luau"),
  '-- require("./missing") is a comment, not an import.\nreturn [=[require("also-not-an-import")]=]\n',
);
const withModule = original
  .replace("--!strict", '--!strict\nlocal message = require("./message")')
  .replace('"HELLO, CONSOLE!"', "message");
await writeFile(main, withModule);
cli(["build", project]);
const bundled = await readFile(resolve(project, "build/web/game.luau"), "utf8");
assert.ok(
  bundled.includes('[=[require("also-not-an-import")]=]'),
  "bundler preserves long strings",
);
assert.ok(bundled.includes('-- require("./missing")'), "bundler preserves comments");
await writeFile(resolve(project, "src/a.luau"), 'return require("./b")\n');
await writeFile(resolve(project, "src/b.luau"), 'return require("./a")\n');
await assert.rejects(
  () =>
    bundleLuau({
      entry: resolve(project, "src/a.luau"),
      project,
      sdkRoot: resolve("sdk/luau"),
      assets: Buffer.alloc(0),
    }),
  /Cyclic require/,
);
await unlink(resolve(project, "src/a.luau"));
await unlink(resolve(project, "src/b.luau"));
// Get an unused local port without assuming a fixed developer port is free.
const reservation = createServer();
reservation.listen(0, "127.0.0.1");
await once(reservation, "listening");
const port = reservation.address().port;
await new Promise((r) => reservation.close(r));
const watcher = spawn(
  process.execPath,
  ["tools/console.mjs", "watch", project, "--web", "--port", String(port), "--fps", "144"],
  { stdio: ["ignore", "pipe", "pipe"] },
);
let output = "";
const append = (data) => {
  output = (output + data).slice(-64000);
};
watcher.stdout.on("data", append);
watcher.stderr.on("data", append);
const waitFor = async (text, count = 1) => {
  const deadline = Date.now() + 20000;
  while (output.split(text).length - 1 < count) {
    if (watcher.exitCode !== null) {
      throw new Error(output);
    }
    if (Date.now() > deadline) {
      throw new Error("CLI deadline: " + output);
    }
    await new Promise((r) => setTimeout(r, 50));
  }
};
try {
  await waitFor("Watching source");
  await waitFor(`Player: http://127.0.0.1:${port}`);
  assert(output.includes(`/player.html?fps=144`));
  const url = `http://127.0.0.1:${port}/game.luau`;
  assert.equal(await (await fetch(url)).text(), bundled);
  await writeFile(resolve(project, "src/message.luau"), 'return "UPDATED MESSAGE"\n');
  await waitFor("Build ready. Reload", 1);
  const changed = await (await fetch(url)).text();
  assert.notEqual(changed, bundled, "watch rebuilds a required module");
  await writeFile(main, original.replace("local game:", 'console.button("jump")\nlocal game:'));
  await waitFor("luau-analyze.exe failed");
  assert.equal(
    await (await fetch(url)).text(),
    changed,
    "failed check leaves last working build available",
  );
  await writeFile(main, withModule + "\n-- recovered\n");
  await waitFor("Build ready. Reload", 2);
  assert.notEqual(await (await fetch(url)).text(), changed, "watch recovers after a type error");
} finally {
  watcher.kill();
  if (watcher.exitCode === null) {
    await once(watcher, "exit");
  }
}
console.log(
  "SDK CLI passed: starter typing, exclusive creation, modules, comments/strings, cycles, static serving, watch rebuild, failed-build preservation and recovery.",
);

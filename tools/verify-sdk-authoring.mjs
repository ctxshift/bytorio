import assert from "node:assert/strict";
import { copyFile, cp, mkdir, mkdtemp, readFile, rename, rm, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { createServer } from "node:http";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { tmpdir } from "node:os";
import { basename, resolve, sep } from "node:path";
import { compileCli } from "./compile-cli.mjs";
import { requireCliHost } from "./host-platform.mjs";
import { repo, run, tool } from "./toolchain.mjs";
import { branding } from "./branding.mjs";
import { exportExecutor, exportPlayer } from "./player-export.mjs";
import { packComponent } from "./sdk/component.mjs";
import { parseSdkManifest } from "./cli/sdk-manifest.mjs";
import { manifestFixture } from "./cli/fixtures/sdk-manifest.mjs";
import { chromium } from "./browser-timing.mjs";
import { serve } from "./serve.mjs";

const host = requireCliHost();
const output = resolve(repo, "build/sdk-authoring-verification");
await mkdir(output, { recursive: true });
const built = resolve(output, host.executable);
compileCli(["tools/cli/authoring-probe.mjs"], built);
const temporaryRoot = resolve(tmpdir());
const sandbox = await mkdtemp(resolve(temporaryRoot, "byt-authoring-consumer-"));
assert.ok(sandbox.startsWith(temporaryRoot + sep));
const server = createServer();
const execute = promisify(execFile);
let browser, website;
try {
  const payloads = resolve(sandbox, "producer payloads");
  const archives = new Map();
  const descriptors = {};
  const ref = (component, path) => ({ component, path });
  const contract = JSON.parse(await readFile(resolve(repo, "sdk/contract.json"), "utf8"));
  const manifest = manifestFixture("0.2.0-preview.1");
  manifest.profiles = contract.profiles;
  manifest.limits = contract.limits;
  manifest.native = {};
  const analyzer = basename(tool("luau-analyze"));
  manifest.languages = {
    luau: {
      libraries: ref("core", "sdk/luau"),
      hosts: { [host.id]: { analyzer: ref("tools", analyzer) } },
    },
  };
  manifest.check = {
    runtime: ref("checks", "runtime.wasm"),
    workers: { luau: ref("checks", "check-worker.mjs") },
    luauExecutor: ref("executor", "luau-executor.wasm"),
  };
  manifest.web = {
    runtime: ref("web", "player.js"),
    player: ref("web", "player.js"),
    page: ref("web", "player.html"),
  };
  manifest.starters = {
    luau: {
      entry: "src/main.luau",
      source: (await readFile(resolve(repo, "sdk/templates/main.luau"), "utf8")).replaceAll(
        "__STARTER_MESSAGE__",
        branding.starterMessage,
      ),
    },
  };

  for (const id of ["core", "tools", "checks", "executor", "web"]) {
    await mkdir(resolve(payloads, id), { recursive: true });
  }
  const core = resolve(payloads, "core");
  await cp(resolve(repo, "sdk"), resolve(core, "sdk"), { recursive: true });
  run(tool("bun"), [
    "build",
    "--target=bun",
    "tools/sdk/authoring.mjs",
    "--outfile",
    resolve(core, "authoring.mjs"),
  ]);
  const checks = resolve(payloads, "checks");
  await copyFile(
    resolve(repo, "build/odin-player/web/runtime.wasm"),
    resolve(checks, "runtime.wasm"),
  );
  await mkdir(resolve(checks, "licenses"));
  await copyFile(
    resolve(repo, "build/odin-player/web/licenses/odin.txt"),
    resolve(checks, "licenses/odin.txt"),
  );
  run(tool("bun"), [
    "build",
    "--target=bun",
    "tools/sdk/smoke-worker.mjs",
    "--outfile",
    resolve(checks, "check-worker.mjs"),
  ]);
  const executor = await exportExecutor({ target: resolve(payloads, "executor") });
  await copyFile(tool("luau-analyze"), resolve(payloads, "tools", analyzer));
  await mkdir(resolve(payloads, "tools/licenses"));
  await copyFile(
    resolve(repo, "build/luau-executor/_deps/luau-src/LICENSE.txt"),
    resolve(payloads, "tools/licenses/luau.txt"),
  );
  await exportPlayer({
    platform: "web",
    source: resolve(repo, "build/odin-player/web"),
    target: resolve(payloads, "web"),
    luau: false,
  });
  const notices = {
    core: ["sdk/NOTICE"],
    tools: ["licenses/luau.txt"],
    checks: ["licenses/odin.txt"],
    executor: executor.notices,
    web: ["licenses/odin.txt", "licenses/vorbis.txt"],
  };
  for (const id of Object.keys(notices)) {
    const asset = `sdk-${id}.tar.gz`;
    const archive = resolve(sandbox, asset);
    const descriptor = await packComponent({
      root: resolve(payloads, id),
      archive,
      notices: notices[id],
      executables: id === "tools" ? [analyzer] : [],
    });
    descriptors[id] = { asset, ...descriptor };
    archives.set(asset, archive);
  }
  manifest.components = descriptors;
  const metadata = Buffer.from(JSON.stringify(manifest));
  parseSdkManifest(metadata, manifest.version);
  const metadataSha256 = createHash("sha256").update(metadata).digest("hex");
  const requests = [];
  server.on("request", async (request, response) => {
    requests.push(request.url);
    const name = new URL(request.url, "http://127.0.0.1").pathname.split("/").at(-1);
    if (name === "sdk-release.json") {
      response.end(metadata);
    } else if (archives.has(name)) {
      response.end(await readFile(archives.get(name)));
    } else {
      response.writeHead(404).end();
    }
  });
  await new Promise((done) => server.listen(0, "127.0.0.1", done));
  const executable = resolve(sandbox, host.executable);
  await copyFile(built, executable);
  const project = resolve(sandbox, "minimal game");
  await mkdir(resolve(project, "src"), { recursive: true });
  await writeFile(resolve(project, "src/main.luau"), manifest.starters.luau.source);
  const cache = resolve(sandbox, "shared SDK cache");
  const options = {
    cache,
    releaseRoot: `http://127.0.0.1:${server.address().port}`,
    expectedSha256: metadataSha256,
  };
  const environment = Object.fromEntries(
    Object.entries(process.env).filter(
      ([name]) => !/^(path|mise.*|node.*|bun.*|validation_.*)$/i.test(name),
    ),
  );
  environment.PATH = "";
  const requestPath = resolve(sandbox, "request.json");
  async function invoke(action, offline = false) {
    await writeFile(
      requestPath,
      JSON.stringify({
        action,
        version: manifest.version,
        project,
        config: { sdkRelease: manifest.version },
        options: { ...options, offline },
      }),
    );
    const result = await execute(executable, [requestPath], {
      cwd: sandbox,
      env: environment,
      windowsHide: true,
      timeout: 60000,
      maxBuffer: 1024 * 1024,
    });
    assert.match(result.stdout, /Standalone SDK authoring passed/);
  }
  await invoke("check");
  assert.ok(
    !requests.some((path) => path.endsWith("sdk-web.tar.gz")),
    "Checking downloaded the web player",
  );
  const checkedRequests = requests.length;
  await invoke("pack", true);
  assert.equal(requests.length, checkedRequests);
  await invoke("build");
  assert.equal(requests.filter((path) => path.endsWith("sdk-web.tar.gz")).length, 1);
  const builtRequests = requests.length;
  await invoke("build", true);
  assert.equal(requests.length, builtRequests);
  const relocated = resolve(sandbox, "site/nested/game");
  await mkdir(resolve(sandbox, "site/nested"), { recursive: true });
  await rename(resolve(project, "build/web"), relocated);
  assert.ok(cache.startsWith(sandbox + sep));
  await rm(cache, { recursive: true, force: true });
  website = serve(resolve(sandbox, "site"), 0);
  await new Promise((done) => website.once("listening", done));
  browser = await chromium.launch({ channel: process.env.PLAYER_BROWSER_CHANNEL || undefined });
  const page = await browser.newPage();
  await page.goto(`http://127.0.0.1:${website.address().port}/nested/game/player.html`);
  await page.waitForFunction(() => playerStatus.ready || playerStatus.error);
  await page.click("#start");
  await page.waitForFunction(() => playerStatus.ticks >= 3 || playerStatus.error);
  const played = await page.evaluate(() => ({
    error: playerStatus.error,
    ticks: playerStatus.ticks,
  }));
  assert.equal(played.error, "");
  assert.ok(played.ticks >= 3);
  await writeFile(
    resolve(output, "report.json"),
    JSON.stringify(
      {
        status: "passed",
        platform: host.id,
        isolatedCwd: true,
        emptyPath: true,
        metadataSha256,
        checkedRequests,
        builtRequests,
        offlinePack: true,
        offlineBuild: true,
        relocatedPlaybackWithoutCache: true,
        played,
      },
      null,
      2,
    ) + "\n",
  );
  console.log(
    "Standalone SDK authoring passed: real managed Luau check/build/pack, offline reuse and relocated browser play without cache.",
  );
} finally {
  await browser?.close();
  await new Promise((done) => (website ? website.close(done) : done()));
  server.closeAllConnections();
  await new Promise((done) => server.close(done));
  await rm(sandbox, { recursive: true, force: true });
}

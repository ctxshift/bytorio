import assert from "node:assert/strict";
import { copyFile, mkdir, mkdtemp, readFile, rename, rm, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { createServer } from "node:http";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { tmpdir } from "node:os";
import { resolve, sep } from "node:path";
import { compileCli } from "./compile-cli.mjs";
import { requireCliHost } from "./host-platform.mjs";
import { repo } from "./toolchain.mjs";
import { produceHostSdk } from "./sdk/produce.mjs";
import { chromium } from "./browser-timing.mjs";
import { serve } from "./serve.mjs";

const host = requireCliHost();
const output = resolve(repo, "build/sdk-authoring-verification");
await mkdir(output, { recursive: true });
await rm(resolve(output, "report.json"), { force: true });
const built = resolve(output, host.executable);
compileCli(["tools/cli/authoring-probe.mjs"], built);
const temporaryRoot = resolve(tmpdir());
const sandbox = await mkdtemp(resolve(temporaryRoot, "byt-authoring-consumer-"));
assert.ok(sandbox.startsWith(temporaryRoot + sep));
const server = createServer();
const execute = promisify(execFile);
let browser, website;
try {
  const { manifest, metadata, archives } = await produceHostSdk({
    version: "0.2.0-preview.1",
    cliVersionRange: ">=0.1.0-0 <1.0.0",
    output: resolve(sandbox, "SDK candidate"),
  });
  await assert.rejects(
    produceHostSdk({
      version: manifest.version,
      cliVersionRange: manifest.cliVersionRange,
      output: resolve(sandbox, "SDK candidate"),
    }),
    { code: "EEXIST" },
  );
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
  const cache = resolve(sandbox, "shared SDK cache");
  const options = {
    cache,
    releaseRoot: `http://127.0.0.1:${server.address().port}`,
    expectedSha256: metadataSha256,
  };
  const environment = Object.fromEntries(
    Object.entries(process.env).filter(
      ([name]) => !/^(path|mise.*|node.*|bun.*|odin.*|validation_.*)$/i.test(name),
    ),
  );
  environment.PATH = "";
  const requestPath = resolve(sandbox, "request.json");
  async function invoke(language, action, { offline = false, targets = ["web"] } = {}) {
    await writeFile(
      requestPath,
      JSON.stringify({
        action,
        version: manifest.version,
        project: resolve(sandbox, `${language} game`),
        config: { language },
        targets,
        options: { ...options, offline },
      }),
    );
    const result = await execute(executable, [requestPath], {
      cwd: sandbox,
      env: environment,
      windowsHide: true,
      timeout: 120000,
      maxBuffer: 1024 * 1024,
    });
    assert.match(result.stdout, /Standalone SDK authoring passed/);
  }
  for (const language of ["luau", "odin"]) {
    const project = resolve(sandbox, `${language} game`);
    await mkdir(resolve(project, "src"), { recursive: true });
    await writeFile(resolve(project, `src/main.${language}`), manifest.starters[language].source);
  }
  await invoke("luau", "check");
  assert.ok(
    !requests.some((path) => path.endsWith(manifest.components.web.asset)),
    "Checking downloaded the web player",
  );
  const odinId = `odin-${host.id}`;
  const nativeId = `native-${host.id}`;
  assert.ok(!requests.some((path) => path.endsWith(manifest.components[odinId].asset)));
  assert.ok(!requests.some((path) => path.endsWith(manifest.components[nativeId].asset)));
  const checkedRequests = requests.length;
  await invoke("luau", "pack", { offline: true });
  assert.equal(requests.length, checkedRequests);
  await invoke("luau", "build");
  assert.equal(requests.filter((path) => path.endsWith(manifest.components.web.asset)).length, 1);
  assert.ok(!requests.some((path) => path.endsWith(manifest.components[odinId].asset)));
  assert.ok(!requests.some((path) => path.endsWith(manifest.components[nativeId].asset)));
  await invoke("odin", "check");
  const odinCheckedRequests = requests.length;
  await invoke("odin", "pack", { offline: true });
  assert.equal(requests.length, odinCheckedRequests);
  for (const language of ["luau", "odin"]) {
    await invoke(language, "build", { targets: ["web", "native"] });
  }
  const builtRequests = requests.length;
  for (const language of ["luau", "odin"]) {
    await invoke(language, "build", { offline: true, targets: ["web", "native"] });
  }
  assert.equal(requests.length, builtRequests);
  await mkdir(resolve(sandbox, "site/nested"), { recursive: true });
  for (const language of ["luau", "odin"]) {
    const project = resolve(sandbox, `${language} game`);
    await rename(resolve(project, "build/web"), resolve(sandbox, `site/nested/${language}`));
    await rename(resolve(project, "build/native"), resolve(sandbox, `${language} native export`));
  }
  assert.ok(cache.startsWith(sandbox + sep));
  await rm(cache, { recursive: true, force: true });
  website = serve(resolve(sandbox, "site"), 0);
  await new Promise((done) => website.once("listening", done));
  browser = await chromium.launch({ channel: process.env.PLAYER_BROWSER_CHANNEL || undefined });
  const played = {};
  for (const language of ["luau", "odin"]) {
    const page = await browser.newPage();
    await page.goto(
      `http://127.0.0.1:${website.address().port}/nested/${language}/player.html?smoke`,
    );
    await page.waitForFunction(() => playerStatus.ready || playerStatus.error);
    await page.click("#start");
    await page.waitForFunction(() => playerStatus.renderedTicks === 120 || playerStatus.error);
    const web = await page.evaluate(() => ({
      error: playerStatus.error,
      ticks: playerStatus.ticks,
      hash: playerStatus.hash,
    }));
    assert.equal(web.error, "");
    assert.equal(web.ticks, 120);
    await page.close();
    const target = resolve(sandbox, `${language} native export`);
    const result = await execute(resolve(target, host.player), ["--smoke", "--no-executor-cache"], {
      cwd: sandbox,
      env: {
        ...environment,
        SDL_VIDEODRIVER: "dummy",
        SDL_AUDIODRIVER: "dummy",
        SDL_RENDER_DRIVER: "software",
      },
      windowsHide: true,
      timeout: 60000,
    });
    const native = JSON.parse(result.stdout);
    assert.equal(native.ticks, 120);
    assert.ok(native.audioQueuedFrames > 0);
    assert.equal(native.hash, web.hash, `${language} relocated native/web starter image`);
    if (process.platform === "darwin") {
      for (const name of [host.player, host.sdlLibrary]) {
        await execute("/usr/bin/codesign", ["--verify", "--strict", resolve(target, name)], {
          cwd: sandbox,
          env: environment,
          timeout: 30000,
        });
      }
    }
    played[language] = { web, native };
  }
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
    "Standalone SDK authoring passed: managed Luau/Odin tools, offline check/build/pack and relocated native/browser play without cache.",
  );
} finally {
  await browser?.close();
  await new Promise((done) => (website ? website.close(done) : done()));
  server.closeAllConnections();
  await new Promise((done) => server.close(done));
  await rm(sandbox, { recursive: true, force: true });
}

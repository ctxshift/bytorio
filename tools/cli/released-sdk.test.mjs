import assert from "node:assert/strict";
import { test } from "node:test";
import { createServer } from "node:http";
import { lstat, mkdir, mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { packComponent } from "../sdk/component.mjs";
import { createReleasedSdk } from "./released-sdk.mjs";

async function fixture(run) {
  const root = await mkdtemp(resolve(tmpdir(), "byt-player-copy-"));
  const components = {};
  const archives = new Map();
  const host = "test-host";
  const manifest = { version: "0.2.0", components, web: {}, native: {}, check: {} };
  const server = createServer(async (request, response) => {
    const archive = archives.get(request.url.split("/").at(-1));
    if (archive) {
      response.end(await readFile(archive));
    } else {
      response.writeHead(404).end();
    }
  });
  await new Promise((done) => server.listen(0, "127.0.0.1", done));
  async function add(id, files, executables = []) {
    const source = resolve(root, id);
    await mkdir(source);
    files = { ...files, "licenses/sdk.txt": "SDK notice\n" };
    for (const [path, data] of Object.entries(files)) {
      const segments = path.split("/");
      await mkdir(resolve(source, ...segments.slice(0, -1)), { recursive: true });
      await writeFile(resolve(source, path), data);
    }
    const asset = `${id}.tar.gz`;
    const archive = resolve(root, asset);
    components[id] = {
      asset,
      ...(await packComponent({
        root: source,
        archive,
        executables,
        notices: ["licenses/sdk.txt"],
      })),
    };
    archives.set(asset, archive);
  }
  const options = {
    host,
    cache: resolve(root, "cache"),
    releaseRoot: `http://127.0.0.1:${server.address().port}`,
  };
  try {
    await run({
      root,
      host,
      manifest,
      options,
      add,
      sdk: () => createReleasedSdk({ manifest }, options),
    });
  } finally {
    server.closeAllConnections();
    await new Promise((done) => server.close(done));
    await rm(root, { recursive: true, force: true });
  }
}

test("released native players copy exact bytes and modes without signing or source builds", async () =>
  fixture(async ({ root, host, manifest, add, sdk }) => {
    const binary = Buffer.from([0, 255, 1, 2, 3, 0, 128]);
    await add("native", { player: binary, "runtime-library.bin": binary }, ["player"]);
    manifest.native[host] = { component: "native", path: "player" };
    const target = resolve(root, "export");
    await sdk().player({ platform: "native", target, luau: false });
    assert.deepEqual(await readFile(resolve(target, "player")), binary);
    if (process.platform !== "win32") {
      assert.equal((await lstat(resolve(target, "player"))).mode & 0o777, 0o755);
    }
    assert.deepEqual(await readFile(resolve(target, "runtime-library.bin")), binary);
    assert.equal(await readFile(resolve(target, "licenses/sdk.txt"), "utf8"), "SDK notice\n");
    await assert.rejects(
      sdk().player({ platform: "native", target, luau: true }),
      /does not include a Luau executor/,
    );
  }));

test("player payloads cannot overwrite game outputs or merge conflicting files", async () =>
  fixture(async ({ root, host, manifest, add, sdk }) => {
    await add("reserved", { player: "binary", "GAME.PNG": "placeholder" }, ["player"]);
    manifest.native[host] = { component: "reserved", path: "player" };
    await assert.rejects(
      sdk().player({ platform: "native", target: resolve(root, "reserved-export") }),
      /conflicts with generated game output/,
    );
    await add("runtime", { "runtime.js": "module", "shared.txt": "first" });
    await add("player", { "player.js": "module", "player.html": "page", "shared.txt": "second" });
    manifest.web = {
      runtime: { component: "runtime", path: "runtime.js" },
      player: { component: "player", path: "player.js" },
      page: { component: "player", path: "player.html" },
    };
    await assert.rejects(
      sdk().player({ platform: "web", target: resolve(root, "conflict-export") }),
      /conflicting files/,
    );
  }));

test("player entrypoints must exist in their own component", async () =>
  fixture(async ({ root, manifest, add, sdk }) => {
    await add("runtime", { "player.js": "wrong component" });
    await add("player", { "player.html": "page" });
    manifest.web = {
      runtime: { component: "runtime", path: "player.js" },
      player: { component: "player", path: "player.js" },
      page: { component: "player", path: "player.html" },
    };
    await assert.rejects(
      sdk().player({ platform: "web", target: resolve(root, "export") }),
      /missing entrypoint player.js/,
    );
  }));

test("player copying rejects existing links inside the export target", async () =>
  fixture(async ({ root, host, manifest, add, sdk }) => {
    await add("native", { player: "binary" }, ["player"]);
    manifest.native[host] = { component: "native", path: "player" };
    const target = resolve(root, "export");
    const outside = resolve(root, "outside");
    await mkdir(target);
    await mkdir(outside);
    await writeFile(resolve(outside, "sdk.txt"), "preserve");
    await symlink(
      outside,
      resolve(target, "licenses"),
      process.platform === "win32" ? "junction" : "dir",
    );
    await assert.rejects(sdk().player({ platform: "native", target }), /without a symlink/);
    assert.equal(await readFile(resolve(outside, "sdk.txt"), "utf8"), "preserve");
  }));

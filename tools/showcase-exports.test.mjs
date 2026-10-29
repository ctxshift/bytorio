import assert from "node:assert/strict";
import { test } from "node:test";
import { mkdtemp, mkdir, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { exportDigest, reusableExport } from "./showcase-exports.mjs";

test("showcase receipts reject missing exports, changed pins and modified player bytes", async () => {
  const root = await mkdtemp(resolve(tmpdir(), "showcase-export-"));
  const web = resolve(root, "build/web");
  assert.equal(await reusableExport(root, "revision-one"), false);
  await mkdir(web, { recursive: true });
  for (const file of ["game.png", "player.html", "runtime.js", "web-player.js"]) {
    await writeFile(resolve(web, file), file);
  }
  await writeFile(
    resolve(root, "build/showcase-export.json"),
    JSON.stringify({
      schema: 1,
      revision: "revision-one",
      digest: await exportDigest(web),
    }),
  );
  assert.equal(await reusableExport(root, "revision-one"), true);
  assert.equal(await reusableExport(root, "revision-two"), false);
  await writeFile(resolve(web, "web-player.js"), "local override");
  assert.equal(await reusableExport(root, "revision-one"), false);
  await rm(resolve(web, "game.png"));
  assert.equal(await reusableExport(root, "revision-one"), false);
});

import assert from "node:assert/strict";
import { test } from "node:test";
import { createHash } from "node:crypto";
import { mkdtemp, readFile, writeFile, readdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { downloadDependency } from "./dependency-download.mjs";

const bytes = Buffer.from("pinned source archive");
const hash = createHash("sha256").update(bytes).digest("hex");
test("transient failures retry, publish verified bytes atomically and reuse the cache", async () => {
  const root = await mkdtemp(join(tmpdir(), "dependency-download-"));
  const destination = join(root, "source.tar");
  let calls = 0;
  const delays = [];
  const options = {
    request: async () => {
      calls++;
      if (calls === 1) {
        throw Object.assign(new Error("reset"), { cause: { code: "ECONNRESET" } });
      }
      if (calls === 2) {
        return new Response("unavailable", { status: 503 });
      }
      return new Response(bytes);
    },
    wait: async (ms) => delays.push(ms),
  };
  await downloadDependency("https://example.com/source", destination, hash, options);
  await downloadDependency("https://example.com/source", destination, hash, options);
  assert.equal(calls, 3);
  assert.deepEqual(delays, [1000, 2000]);
  assert.deepEqual(await readFile(destination), bytes);
  assert.deepEqual(await readdir(root), ["source.tar"]);
});

test("checksum failures and permanent errors never retry or poison the cache", async () => {
  const root = await mkdtemp(join(tmpdir(), "dependency-download-"));
  const destination = join(root, "source.tar");
  for (const response of [
    () => new Response("wrong"),
    () => new Response("missing", { status: 404 }),
  ]) {
    let calls = 0;
    await assert.rejects(
      downloadDependency("https://example.com/source", destination, hash, {
        request: async () => {
          calls++;
          return response();
        },
      }),
    );
    assert.equal(calls, 1);
    assert.deepEqual(await readdir(root), []);
  }
  await writeFile(destination, "corrupt cache");
  await assert.rejects(
    downloadDependency("https://example.com/source", destination, hash),
    /Cached dependency checksum/,
  );
});

test("persistent transient failure stops after three attempts without publishing", async () => {
  const root = await mkdtemp(join(tmpdir(), "dependency-download-"));
  let calls = 0;
  await assert.rejects(
    downloadDependency("https://example.com/source", join(root, "archive"), hash, {
      request: async () => {
        calls++;
        return new Response("busy", { status: 503 });
      },
      wait: async () => {},
    }),
    /HTTP 503/,
  );
  assert.equal(calls, 3);
  assert.deepEqual(await readdir(root), []);
});

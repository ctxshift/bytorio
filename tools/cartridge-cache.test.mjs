import assert from "node:assert/strict";
import test from "node:test";
import { fetchCartridge } from "../runtime/odin/web/cartridge-cache.js";
import { MAX_CARTRIDGE_BYTES } from "../runtime/odin/web/constants.js";

function fixture(failure) {
  const entries = new Map();
  let requests = 0;
  const options = {
    fetchResponse: async () => {
      requests++;
      return new Response(new Uint8Array([requests, 2, 3, 4]));
    },
    cacheStorage: {
      async open() {
        if (failure === "open") {
          throw new Error("storage unavailable");
        }
        return {
          async match(key) {
            if (failure === "match") {
              throw new Error("storage read failed");
            }
            const bytes = entries.get(key);
            return bytes ? new Response(bytes) : undefined;
          },
          async put(key, response) {
            if (failure === "put") {
              throw new Error("storage quota exceeded");
            }
            entries.set(key, await response.arrayBuffer());
          },
          async keys() {
            return [...entries.keys()].map((url) => new Request(url));
          },
          async delete(request) {
            return entries.delete(request.url);
          },
        };
      },
    },
  };
  return { options, entries, requests: () => requests };
}

const url = (revision) => new URL(`https://example.test/game.png?revision=${revision.repeat(64)}`);

test("refresh reuses exact cached bytes and new revisions fetch fresh bytes", async () => {
  const state = fixture();
  const first = await (await fetchCartridge(url("a"), state.options)).arrayBuffer();
  const again = await (await fetchCartridge(url("a"), state.options)).arrayBuffer();
  assert.deepEqual(again, first);
  assert.equal(state.requests(), 1);
  const changed = await (await fetchCartridge(url("b"), state.options)).arrayBuffer();
  assert.notDeepEqual(changed, first);
  await fetchCartridge(url("c"), state.options);
  assert.equal(state.entries.size, 2);
  assert(!state.entries.has(url("a").href));
  assert(state.entries.has(url("b").href));
  assert(state.entries.has(url("c").href));
});

test("storage denial, read errors and quota failures leave network loading usable", async () => {
  for (const failure of ["open", "match", "put"]) {
    const state = fixture(failure);
    const response = await fetchCartridge(url("a"), state.options);
    assert.equal((await response.arrayBuffer()).byteLength, 4);
    assert.equal(state.requests(), failure === "put" ? 2 : 1);
  }
});

test(
  "failed storage writes abort the original stream before the uncached retry",
  { timeout: 1000 },
  async () => {
    const state = fixture("put");
    let cancelled = 0;
    const body = new ReadableStream({
      start(controller) {
        controller.enqueue(new Uint8Array([1, 2, 3, 4]));
      },
      cancel() {
        cancelled++;
      },
    });
    let calls = 0;
    state.options.fetchResponse = async () => {
      calls++;
      return calls === 1 ? new Response(body) : new Response(new Uint8Array([5, 6]));
    };
    const response = await fetchCartridge(url("a"), state.options);
    assert.deepEqual(new Uint8Array(await response.arrayBuffer()), new Uint8Array([5, 6]));
    await new Promise((accept) => setImmediate(accept));
    assert.equal(cancelled, 1);
    assert.equal(body.locked, false);
    assert.equal(calls, 2);
  },
);

test("local files and unversioned or malformed URLs bypass persistent storage", async () => {
  const state = fixture();
  const file = new Blob([new Uint8Array([1, 2, 3, 4])]);
  assert.equal(await fetchCartridge(file, state.options), file);
  assert.equal(state.requests(), 0);
  for (const source of [
    "https://example.test/game.png",
    "https://example.test/game.png?revision=bad",
    `${url("a")}&revision=${"b".repeat(64)}`,
  ]) {
    await fetchCartridge(source, state.options);
    await fetchCartridge(source, state.options);
  }
  assert.equal(state.requests(), 6);
  assert.equal(state.entries.size, 0);
});

test("stream errors, length mismatch and callback failure never commit cached bytes", async () => {
  for (const mode of ["length", "oversized", "callback", "empty"]) {
    const state = fixture();
    let cancelled = 0;
    const stream = new ReadableStream({
      start(controller) {
        if (mode !== "empty") {
          controller.enqueue(new Uint8Array([1, 2, 3, 4]));
        }
        if (mode !== "oversized") {
          controller.close();
        }
      },
      cancel() {
        cancelled++;
      },
    });
    const length = mode === "oversized" ? MAX_CARTRIDGE_BYTES + 1 : 5;
    state.options.fetchResponse = async () =>
      new Response(stream, {
        headers:
          mode === "callback" || mode === "empty" ? {} : { "Content-Length": String(length) },
      });
    if (mode === "callback") {
      state.options.onProgress = () => {
        throw new Error("observer failed");
      };
    }
    await assert.rejects(fetchCartridge(url("a"), state.options), /size|length|observer/);
    assert.equal(state.entries.size, 0);
    if (mode === "oversized") {
      assert.equal(cancelled, 1);
    }
  }
});

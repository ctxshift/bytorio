import test from "node:test";
import assert from "node:assert/strict";
import { loadCartridge } from "../runtime/odin/web/cartridge.js";

function fixture(limit = 1024) {
  const reservations = [];
  const runtime = {
    memory: { buffer: new ArrayBuffer(16) },
    runtime_cartridge_capacity: () => limit,
    runtime_cartridge_reserve: (length) => {
      reservations.push(length);
      runtime.memory.buffer = new ArrayBuffer(length + 16);
      return length ? 16 : 0;
    },
    runtime_cartridge_parse: () => 2,
    runtime_cartridge_profile: () => 1,
    runtime_cartridge_sdk: () => 256,
    runtime_cartridge_abi: () => 1,
    runtime_cartridge_title: () => 0,
    runtime_cartridge_title_size: () => 0,
    runtime_cartridge_display: () => (640 << 16) | 360,
    runtime_cartridge_code: () => 16,
    runtime_cartridge_code_size: () => 4,
  };
  return { runtime, reservations };
}

test("known-size HTTP and Blob cartridges stream into one exact runtime allocation", async () => {
  const bytes = Uint8Array.from({ length: 300 }, (_, index) => index % 251);
  for (const source of [
    new Blob([bytes]),
    new Response(bytes, { headers: { "Content-Length": "300" } }),
  ]) {
    source.arrayBuffer = () => {
      throw new Error("whole input copy is forbidden");
    };
    const { runtime, reservations } = fixture();
    const result = await loadCartridge(runtime, source);
    assert.deepEqual(reservations, [300]);
    assert.equal(result.length, 300);
    assert.deepEqual(new Uint8Array(runtime.memory.buffer, 16), bytes);
    assert.deepEqual(result.code, bytes.subarray(0, 4));
    new Uint8Array(runtime.memory.buffer, 16, 4).fill(0);
    assert.deepEqual(result.code, bytes.subarray(0, 4), "small executable copy owns its bytes");
  }
});

test("HTTP length mismatches, oversized bodies and failed streams clear prior ownership", async () => {
  for (const [declared, actual, message] of [
    [3, 4, /mismatch/],
    [5, 4, /mismatch/],
    [1025, 4, /size/],
  ]) {
    const { runtime, reservations } = fixture();
    await assert.rejects(
      loadCartridge(
        runtime,
        new Response(new Uint8Array(actual), {
          headers: { "Content-Length": String(declared) },
        }),
      ),
      message,
    );
    assert.equal(reservations.at(-1), 0);
  }
  const { runtime, reservations } = fixture();
  const failed = new ReadableStream({
    start(controller) {
      controller.error(new Error("transfer failed"));
    },
  });
  await assert.rejects(
    loadCartridge(
      runtime,
      new Response(failed, {
        headers: { "Content-Length": "4" },
      }),
    ),
    /transfer failed/,
  );
  assert.deepEqual(reservations, [4, 0]);
  reservations.length = 0;
  const failedOversized = new ReadableStream({
    start(controller) {
      controller.error(new Error("already failed"));
    },
  });
  await assert.rejects(
    loadCartridge(
      runtime,
      new Response(failedOversized, {
        headers: { "Content-Length": "1025" },
      }),
    ),
    /size/,
  );
  assert.deepEqual(reservations, [0], "failed cancellation still clears previous backing");
});

test("chunked and compressed responses use decoded lengths with a bounded fallback", async () => {
  const expected = new Uint8Array([1, 2, 3, 4]);
  for (const headers of [{}, { "Content-Length": "2", "Content-Encoding": "gzip" }]) {
    const { runtime, reservations } = fixture();
    const result = await loadCartridge(runtime, new Response(expected, { headers }));
    assert.equal(result.length, 4);
    assert.deepEqual(reservations, [4]);
    assert.deepEqual(new Uint8Array(runtime.memory.buffer, 16), expected);
  }
  const { runtime, reservations } = fixture(3);
  await assert.rejects(loadCartridge(runtime, new Response(expected)), /size/);
  assert.deepEqual(reservations, [0]);
});

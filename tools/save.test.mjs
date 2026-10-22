import assert from "node:assert/strict";
import test from "node:test";
import { createSaveSlot } from "../runtime/odin/web/save.js";

test("save writes snapshot, serialize, and expose only committed bytes", async () => {
  const memory = new WebAssembly.Memory({ initial: 1, maximum: 2 });
  let complete;
  const slot = createSaveSlot(() => ({ memory }), {
    initial: Uint8Array.of(1, 2, 3),
    commit: () =>
      new Promise((resolve) => {
        complete = resolve;
      }),
  });
  const host = slot.imports;
  new Uint8Array(memory.buffer, 10, 4).set([7, 8, 9, 10]);
  assert.equal(host.save_write(10, 4), 2);
  assert.equal(host.save_status(), 2);
  assert.equal(host.save_size(), 3);
  assert.equal(host.save_write(10, 4), 3, "concurrent write rejected");
  new Uint8Array(memory.buffer, 10, 4).fill(0);
  await Promise.resolve();
  complete();
  await slot.settled();
  assert.equal(host.save_status(), 1);
  memory.grow(1);
  assert.equal(host.save_read(70000, 4096), 4);
  assert.deepEqual([...new Uint8Array(memory.buffer, 70000, 4)], [7, 8, 9, 10]);
});

test("save failures preserve previous snapshot and enforce independent bounds", async () => {
  const memory = new WebAssembly.Memory({ initial: 1 });
  const slot = createSaveSlot(() => ({ memory }), {
    initial: Uint8Array.of(11, 12, 13),
    commit: async () => {
      throw new Error("quota");
    },
  });
  const host = slot.imports;
  new Uint8Array(memory.buffer).fill(123);
  for (const [pointer, length] of [
    [0, 0],
    [0, 65537],
    [65535, 2],
    [-1, 4],
  ]) {
    assert.equal(host.save_write(pointer, length), 3);
  }
  assert.equal(host.save_read(0, 2), 0);
  assert.equal(host.save_read(65535, 3), 0);
  assert.equal(host.save_read(0, 65537), 0);
  assert.deepEqual([...new Uint8Array(memory.buffer, 0, 3)], [123, 123, 123]);
  assert.equal(host.save_write(0, 65536), 2);
  await slot.settled();
  assert.equal(host.save_status(), 3);
  assert.equal(host.save_read(0, 4096), 3);
  assert.deepEqual([...new Uint8Array(memory.buffer, 0, 3)], [11, 12, 13]);
});

test("invalid stored records can be replaced and the per-tick allowance remains bounded", async () => {
  const memory = new WebAssembly.Memory({ initial: 1 });
  const slot = createSaveSlot(() => ({ memory }), {
    initial: new Uint8Array(65537),
    commit: async () => {},
  });
  const host = slot.imports;
  assert.equal(host.save_size(), 0);
  assert.equal(host.save_status(), 3);
  assert.equal(host.save_write(0, 1), 2);
  await slot.settled();
  assert.equal(host.save_status(), 1);
  assert.equal(host.save_write(0, 2), 3, "one accepted write per tick even after completion");
  slot.beginTick();
  assert.equal(host.save_write(0, 2), 2);
  await slot.settled();
  assert.equal(host.save_size(), 2);
});

test("64 KiB pending snapshots retain legacy records and own their complete payload", async () => {
  const memory = new WebAssembly.Memory({ initial: 3 });
  const legacy = Uint8Array.from({ length: 4096 }, (_, index) => index % 251);
  const expected = Uint8Array.from({ length: 65536 }, (_, index) => (index * 37 + 11) % 256);
  let complete;
  const slot = createSaveSlot(() => ({ memory }), {
    initial: legacy,
    commit: () =>
      new Promise((resolve) => {
        complete = resolve;
      }),
  });
  const host = slot.imports;
  const staging = new Uint8Array(memory.buffer, 0, 65536);
  const destination = new Uint8Array(memory.buffer, 65536, 65536);
  staging.set(expected);
  destination.fill(123);
  assert.equal(host.save_write(0, 65536), 2);
  staging.fill(0);
  assert.equal(host.save_read(65536, 65536), 4096, "pending read retains the old snapshot");
  assert.deepEqual(destination.subarray(0, 4096), legacy);
  assert(destination.subarray(4096).every((value) => value === 123));
  slot.beginTick();
  assert.equal(host.save_write(0, 1), 3, "a later tick cannot replace a pending snapshot");
  await Promise.resolve();
  complete();
  await slot.settled();
  assert.equal(host.save_status(), 1);
  assert.equal(host.save_read(65536, 65536), 65536);
  assert.deepEqual(destination, expected);
  assert.equal(host.save_write(0, 65537), 3, "bound is independent of available guest memory");
  assert.equal(host.save_status(), 1);
  assert.equal(host.save_read(65536, 65536), 65536);
  assert.deepEqual(destination, expected);
});

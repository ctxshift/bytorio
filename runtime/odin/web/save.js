import { MAX_SAVE_BYTES, SAVE_EMPTY, SAVE_READY, SAVE_PENDING, SAVE_ERROR } from "./constants.js";

export const unavailableSaveImports = Object.freeze({
  save_size: () => 0,
  save_status: () => SAVE_ERROR,
  save_read: () => 0,
  save_write: () => SAVE_ERROR,
});

// Reads expose the last committed snapshot. A pending write owns its own copy.
export function createSaveSlot(getGame, { initial = new Uint8Array(), commit } = {}) {
  const validInitial = initial instanceof Uint8Array && initial.length <= MAX_SAVE_BYTES;
  let bytes = validInitial ? initial.slice() : new Uint8Array();
  let state = !validInitial || !commit ? SAVE_ERROR : bytes.length ? SAVE_READY : SAVE_EMPTY;
  let pending = Promise.resolve();
  let writeAllowed = true;
  function view(pointer, length) {
    pointer >>>= 0;
    length >>>= 0;
    const memory = getGame()?.memory;
    if (!memory || length > MAX_SAVE_BYTES || pointer + length > memory.buffer.byteLength) {
      return null;
    }
    return new Uint8Array(memory.buffer, pointer, length);
  }
  return {
    imports: {
      save_size: () => bytes.length,
      save_status: () => state,
      save_read: (pointer, capacity) => {
        const destination = view(pointer, capacity);
        if (!destination || destination.length < bytes.length) {
          return 0;
        }
        destination.set(bytes);
        return bytes.length;
      },
      save_write: (pointer, length) => {
        const source = view(pointer, length);
        if (!source?.length || !commit || state === SAVE_PENDING || !writeAllowed) {
          return SAVE_ERROR;
        }
        writeAllowed = false;
        const snapshot = source.slice();
        state = SAVE_PENDING;
        pending = Promise.resolve()
          .then(() => commit(snapshot))
          .then(
            () => {
              bytes = snapshot;
              state = SAVE_READY;
            },
            () => {
              state = SAVE_ERROR;
            },
          );
        return SAVE_PENDING;
      },
    },
    settled: () => pending,
    beginTick: () => {
      writeAllowed = true;
    },
  };
}

export async function openSaveSlot(identity, getGame) {
  let database;
  try {
    const digest = await crypto.subtle.digest("SHA-256", identity);
    const key = [...new Uint8Array(digest)]
      .map((byte) => byte.toString(16).padStart(2, "0"))
      .join("");
    database = await new Promise((resolve, reject) => {
      const request = indexedDB.open("bytorio-saves-v1", 1);
      request.onupgradeneeded = () => request.result.createObjectStore("slots");
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
      request.onblocked = () => reject(new Error("Save database is blocked"));
    });
    const initial = await new Promise((resolve, reject) => {
      const transaction = database.transaction("slots", "readonly");
      const request = transaction.objectStore("slots").get(key);
      transaction.oncomplete = () =>
        resolve(
          request.result === undefined
            ? new Uint8Array()
            : request.result?.length === 0
              ? null
              : request.result,
        );
      transaction.onerror = transaction.onabort = () => reject(transaction.error);
    });
    const slot = createSaveSlot(getGame, {
      initial,
      commit: (snapshot) =>
        new Promise((resolve, reject) => {
          const transaction = database.transaction("slots", "readwrite");
          transaction.objectStore("slots").put(snapshot, key);
          transaction.oncomplete = () => resolve();
          transaction.onerror = transaction.onabort = () => reject(transaction.error);
        }),
    });
    return { ...slot, close: () => database.close() };
  } catch {
    database?.close();
    return {
      imports: unavailableSaveImports,
      settled: () => Promise.resolve(),
      beginTick() {},
      close() {},
    };
  }
}

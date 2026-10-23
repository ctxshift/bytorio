import { MAX_CONTENT_READ_BYTES } from "./constants.js";

// Decode through the same Odin parser used by the standalone native player.
export function decodeCartridge(runtime, bytes) {
  const input = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  if (!input.length || input.length > runtime.runtime_cartridge_capacity()) {
    runtime.runtime_cartridge_reserve(0);
    throw new Error("Invalid PNG cartridge size");
  }
  const pointer = runtime.runtime_cartridge_reserve(input.length);
  if (!pointer) {
    throw new Error("Cannot allocate cartridge input");
  }
  new Uint8Array(runtime.memory.buffer, pointer, input.length).set(input);
  return parseReservedCartridge(runtime, input.length);
}

function parseReservedCartridge(runtime, length) {
  const language = runtime.runtime_cartridge_parse(length);
  const read = (offset, length) => new Uint8Array(runtime.memory.buffer, offset, length);
  const text = new TextDecoder("utf-8", { fatal: true });
  if (!language) {
    throw new Error(
      text.decode(read(runtime.runtime_cartridge_error(), runtime.runtime_cartridge_error_size())),
    );
  }
  return {
    language: language === 1 ? "luau" : "odin",
    profile: runtime.runtime_cartridge_profile(),
    sdk: runtime.runtime_cartridge_sdk(),
    abi: runtime.runtime_cartridge_abi(),
    title: text.decode(
      read(runtime.runtime_cartridge_title(), runtime.runtime_cartridge_title_size()),
    ),
    saveId: text.decode(
      read(runtime.runtime_cartridge_save_id(), runtime.runtime_cartridge_save_id_size()),
    ),
    saveLegacy: read(
      runtime.runtime_cartridge_save_legacy(),
      runtime.runtime_cartridge_save_legacy_size(),
    ).slice(),
    display: runtime.runtime_cartridge_display(),
    code: read(runtime.runtime_cartridge_code(), runtime.runtime_cartridge_code_size()).slice(),
  };
}

// Blob/File messages share immutable browser storage. Known-length HTTP bodies
// and files stream directly into the one runtime-owned cartridge allocation.
export async function loadCartridge(runtime, source, { onProgress } = {}) {
  if (source instanceof ArrayBuffer || source instanceof Uint8Array) {
    const cartridge = decodeCartridge(runtime, source);
    return { ...cartridge, length: source.byteLength };
  }
  const limit = runtime.runtime_cartridge_capacity();
  let stream, length;
  if (source instanceof Blob) {
    length = source.size;
    stream = source.stream();
  } else if (source instanceof Response) {
    if (!source.ok || !source.body) {
      await source.body?.cancel().catch(() => {});
      runtime.runtime_cartridge_reserve(0);
      throw new Error("Could not load PNG cartridge.");
    }
    const header = source.headers.get("content-length");
    const encoding = source.headers.get("content-encoding");
    if (header !== null && /^\d+$/.test(header) && (!encoding || encoding === "identity")) {
      length = Number(header);
      stream = source.body;
    } else {
      // A compressed or chunked response has no reliable decoded length.
      // Retain bounded chunks as a Blob, avoiding a second contiguous JS array.
      const reader = source.body.getReader(),
        parts = [];
      let size = 0;
      try {
        while (true) {
          const { value, done } = await reader.read();
          if (done) {
            break;
          }
          size += value.byteLength;
          if (size > limit) {
            throw new Error("Invalid PNG cartridge size");
          }
          parts.push(value);
          onProgress?.(size, 0);
        }
      } catch (error) {
        await reader.cancel().catch(() => {});
        runtime.runtime_cartridge_reserve(0);
        throw error;
      } finally {
        reader.releaseLock();
      }
      onProgress?.(size, size);
      return loadCartridge(runtime, new Blob(parts));
    }
  } else {
    runtime.runtime_cartridge_reserve(0);
    throw new Error("Invalid PNG cartridge input");
  }
  if (!Number.isSafeInteger(length) || length < 1 || length > limit) {
    await stream.cancel().catch(() => {});
    runtime.runtime_cartridge_reserve(0);
    throw new Error("Invalid PNG cartridge size");
  }
  const pointer = runtime.runtime_cartridge_reserve(length);
  if (!pointer) {
    await stream.cancel().catch(() => {});
    throw new Error("Cannot allocate cartridge input");
  }
  const reader = stream.getReader();
  let offset = 0;
  try {
    onProgress?.(0, length);
    while (true) {
      const { value, done } = await reader.read();
      if (done) {
        break;
      }
      if (value.byteLength > length - offset) {
        throw new Error("PNG cartridge length mismatch");
      }
      new Uint8Array(runtime.memory.buffer, pointer + offset, value.byteLength).set(value);
      offset += value.byteLength;
      onProgress?.(offset, length);
    }
    if (offset !== length) {
      throw new Error("PNG cartridge length mismatch");
    }
    return { ...parseReservedCartridge(runtime, length), length };
  } catch (error) {
    await reader.cancel().catch(() => {});
    runtime.runtime_cartridge_reserve(0);
    throw error;
  } finally {
    reader.releaseLock();
  }
}

// The runtime owns the parsed content. Resolve views afresh after memory growth.
export function contentImports(runtime, getGame, enabled = true) {
  return {
    content_size: (id) => (enabled ? runtime.runtime_content_size(id >>> 0) : 0),
    content_read: (id, offset, pointer, length) => {
      id >>>= 0;
      offset >>>= 0;
      pointer >>>= 0;
      length >>>= 0;
      const memory = getGame()?.memory;
      const size = enabled ? runtime.runtime_content_size(id) : 0;
      if (
        !size ||
        !memory ||
        length > MAX_CONTENT_READ_BYTES ||
        offset + length > size ||
        pointer + length > memory.buffer.byteLength
      ) {
        return 0;
      }
      const source = new Uint8Array(
        runtime.memory.buffer,
        runtime.runtime_content_pointer(id) + offset,
        length,
      );
      new Uint8Array(memory.buffer, pointer, length).set(source);
      return 1;
    },
  };
}

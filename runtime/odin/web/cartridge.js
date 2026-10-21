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
  const language = runtime.runtime_cartridge_parse(input.length);
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
    display: runtime.runtime_cartridge_display(),
    code: read(runtime.runtime_cartridge_code(), runtime.runtime_cartridge_code_size()).slice(),
  };
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

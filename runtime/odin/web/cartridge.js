// Decode through the same Odin parser used by the standalone native player.
export function decodeCartridge(runtime, bytes) {
  const input = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  if (!input.length || input.length > runtime.runtime_cartridge_capacity()) {
    throw new Error("Invalid PNG cartridge size");
  }
  new Uint8Array(runtime.memory.buffer, runtime.runtime_cartridge_buffer(), input.length).set(
    input,
  );
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

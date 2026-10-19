export const FRAME_BYTES = 40;
export const MAX_GAME_BYTES = 1024 * 1024;
export const MAX_PAGES = 128;

export function inspectGuest(bytes) {
  const data = new Uint8Array(bytes);
  if (data.length > MAX_GAME_BYTES) throw new Error('Game module exceeds prototype size limit.');
  if (data.length < 8 || data.slice(0, 8).some((v, i) => v !== [0, 97, 115, 109, 1, 0, 0, 0][i])) {
    throw new Error('Invalid Wasm game header.');
  }
  let cursor = 8;
  function leb(end) {
    let value = 0, shift = 0;
    for (let i = 0; i < 5; i++) {
      if (cursor >= end) throw new Error('Truncated Wasm section.');
      const byte = data[cursor++];
      if (i === 4 && byte > 15) throw new Error('Invalid Wasm integer.');
      value += (byte & 127) * 2 ** shift;
      if (!(byte & 128)) return value;
      shift += 7;
    }
    throw new Error('Invalid Wasm integer.');
  }
  let hasMemory = false;
  while (cursor < data.length) {
    const section = data[cursor++];
    const size = leb(data.length);
    const end = cursor + size;
    if (end > data.length) throw new Error('Truncated Wasm section.');
    if (section === 5) {
      if (hasMemory || leb(end) !== 1) throw new Error('Game must define one memory.');
      const flags = leb(end), initial = leb(end), maximum = flags === 1 ? leb(end) : Infinity;
      if (flags !== 1 || initial > maximum || maximum > MAX_PAGES) throw new Error('Game memory must declare an 8 MiB maximum or less.');
      if (cursor !== end) throw new Error('Invalid memory declaration.');
      hasMemory = true;
    }
    cursor = end;
  }
  if (!hasMemory) throw new Error('Game must define bounded memory.');
  const module = new WebAssembly.Module(data);
  for (const item of WebAssembly.Module.imports(module)) {
    if (item.module !== 'env' || item.name !== 'sin' || item.kind !== 'function') throw new Error('Unsupported game import.');
  }
  const exports = new Map(WebAssembly.Module.exports(module).map(item => [item.name, item.kind]));
  for (const name of ['game_abi', 'game_frame_size', 'game_init', 'game_update', 'game_draw']) {
    if (exports.get(name) !== 'function') throw new Error(`Missing game export: ${name}.`);
  }
  if (exports.get('memory') !== 'memory') throw new Error('Game must export memory.');
  return module;
}

export function readFrame(game) {
  const offset = game.game_draw();
  checkExecutor(game);
  const memory = game.memory.buffer;
  if (!Number.isInteger(offset) || offset < 0 || offset > memory.byteLength - FRAME_BYTES) {
    throw new Error('Frame offset outside guest memory.');
  }
  const bytes = new Uint8Array(memory, offset, FRAME_BYTES);
  const view = new DataView(memory, offset, FRAME_BYTES);
  return { bytes, ticks: view.getUint32(16, true), sounds: view.getUint32(20, true),
    spriteX: view.getInt32(8, true), spriteY: view.getInt32(12, true),
    x: view.getFloat64(24, true), y: view.getFloat64(32, true) };
}

export function checkExecutor(game) {
  if (!game.game_error_length) return;
  const length=game.game_error_length();
  if(!Number.isInteger(length)||length<0||length>1024)throw new Error('Invalid executor diagnostic.');
  if(!length)return;
  const offset=game.game_error();
  if(!Number.isInteger(offset)||offset<0||offset>game.memory.buffer.byteLength-length)throw new Error('Executor diagnostic outside memory.');
  throw new Error(new TextDecoder().decode(new Uint8Array(game.memory.buffer,offset,length)));
}

export function loadSource(game,source) {
  const bytes=new Uint8Array(source);
  if(!bytes.length||bytes.length>256*1024||typeof game.game_source_buffer!=='function'||typeof game.game_source_capacity!=='function'||typeof game.game_source_size!=='function')throw new Error('Invalid source or executor.');
  const offset=game.game_source_buffer(),capacity=game.game_source_capacity();
  if(bytes.length>capacity||!Number.isInteger(offset)||offset<0||offset>game.memory.buffer.byteLength-bytes.length)throw new Error('Source outside executor memory.');
  new Uint8Array(game.memory.buffer,offset,bytes.length).set(bytes);
  game.game_source_size(bytes.length);
}

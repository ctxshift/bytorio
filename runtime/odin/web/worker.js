import { inspectGuest, readFrame, FRAME_BYTES } from './policy.js';

let game, runtime;
let smoke = false;
let lastTick = 0;
const imports = { env: { sin: Math.sin } };

async function fetchBytes(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Could not load ${new URL(url, location.href).pathname}.`);
  const bytes = await response.arrayBuffer();
  if (bytes.byteLength > 1024 * 1024) throw new Error('Module exceeds prototype size limit.');
  return bytes;
}

function frame() {
  const record = readFrame(game);
  const target = runtime.runtime_frame();
  new Uint8Array(runtime.memory.buffer, target, FRAME_BYTES).set(record.bytes);
  if (runtime.runtime_render() !== 1) throw new Error('Invalid frame command.');
  const pixels = new Uint8ClampedArray(runtime.memory.buffer, runtime.runtime_pixels(), 384 * 216 * 4).slice();
  lastTick = record.ticks;
  return { pixels: pixels.buffer, ticks: record.ticks, sounds: record.sounds, spriteX: record.spriteX,
    spriteY: record.spriteY, x: record.x, y: record.y, hash: runtime.runtime_hash() >>> 0 };
}

self.onmessage = async ({ data }) => {
  try {
    if (data.type === 'load') {
      const url = new URL(data.gameUrl, location.href);
      if (url.origin !== location.origin) throw new Error('Game URL must use the player origin.');
      const [gameBytes, runtimeBytes] = await Promise.all([fetchBytes(url), fetchBytes('./runtime.wasm')]);
      self.postMessage({ type: 'executing' });
      game = (await WebAssembly.instantiate(inspectGuest(gameBytes), imports)).exports;
      runtime = (await WebAssembly.instantiate(runtimeBytes, imports)).instance.exports;
      if (game.game_abi() !== 1 || game.game_frame_size() !== FRAME_BYTES) throw new Error('Unsupported game ABI or frame size.');
      runtime.runtime_init();
      game.game_init();
      smoke = !!data.smoke;
      const sample = new Float32Array(runtime.memory.buffer, runtime.runtime_sample(), 16000).slice();
      const output = frame();
      self.postMessage({ type: 'ready', ...output, sample: sample.buffer }, [output.pixels, sample.buffer]);
    } else if (data.type === 'step') {
      if (!game || !Number.isInteger(data.steps) || data.steps < 1 || data.steps > 5) throw new Error('Invalid step request.');
      let output;
      for (let i = 0; i < data.steps && (!smoke || lastTick < 120); i++) {
        const buttons = smoke ? (lastTick < 60 ? 2 : lastTick === 60 ? 16 : 0) : data.input.buttons;
        game.game_update(buttons, smoke ? 0 : Number(data.input.pointer), smoke ? 0 : data.input.x, smoke ? 0 : data.input.y);
        output = frame();
      }
      if (output) self.postMessage({ type: 'frame', ...output }, [output.pixels]);
    } else throw new Error('Unknown player request.');
  } catch (error) {
    self.postMessage({ type: 'error', error: error.message || String(error) });
  }
};

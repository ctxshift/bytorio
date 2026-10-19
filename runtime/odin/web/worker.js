import {
  inspectGuest,
  checkExecutor,
  loadSource,
  uploadGraphics,
  submitDrawing,
  rasterizeDrawing,
  FRAME_BYTES,
} from "./policy.js";

let game, runtime;
let smoke = false;
let lastTick = 0;
const imports = { env: { sin: Math.sin } };
let startup;
let initialMemory;

async function fetchBytes(url) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Could not load ${new URL(url, location.href).pathname}.`);
  }
  const bytes = await response.arrayBuffer();
  if (bytes.byteLength > 1024 * 1024) {
    throw new Error("Module exceeds prototype size limit.");
  }
  return bytes;
}

function submit() {
  return submitDrawing(game, runtime);
}
function rasterize(drawing) {
  rasterizeDrawing(runtime, drawing);
}
function frame() {
  const drawing = submit();
  const { record } = drawing;
  rasterize(drawing);
  const pixels = new Uint8ClampedArray(
    runtime.memory.buffer,
    runtime.runtime_pixels(),
    drawing.width * drawing.height * 4,
  ).slice();
  lastTick = record.ticks;
  return {
    width: drawing.width,
    height: drawing.height,
    pixels: pixels.buffer,
    ticks: record.ticks,
    sounds: record.sounds,
    spriteX: record.spriteX,
    spriteY: record.spriteY,
    x: record.x,
    y: record.y,
    hash: runtime.runtime_hash() >>> 0,
  };
}

self.onmessage = async ({ data }) => {
  try {
    if (data.type === "load") {
      const url = new URL(data.gameUrl, location.href);
      if (url.origin !== location.origin) {
        throw new Error("Game URL must use the player origin.");
      }
      const start = performance.now();
      const isSource = url.pathname.endsWith(".luau");
      const executor = isSource ? data.executor : null;
      const [gameBytes, runtimeBytes, source] = await Promise.all([
        executor ? executor.bytes : fetchBytes(isSource ? "./luau-executor.wasm" : url),
        fetchBytes("./runtime.wasm"),
        isSource ? fetchBytes(url) : null,
      ]);
      const fetched = performance.now();
      self.postMessage({ type: "executing" });
      const gameModule = inspectGuest(gameBytes, executor?.module),
        runtimeModule = new WebAssembly.Module(runtimeBytes);
      const compiled = performance.now();
      game = (await WebAssembly.instantiate(gameModule, imports)).exports;
      runtime = (await WebAssembly.instantiate(runtimeModule, imports)).exports;
      const instantiated = performance.now();
      initialMemory = game.memory.buffer.byteLength;
      if (game.game_abi() !== 1 || game.game_frame_size() !== FRAME_BYTES) {
        throw new Error("Unsupported game ABI or frame size.");
      }
      runtime.runtime_init();
      const runtimeInitialized = performance.now();
      game._initialize?.();
      if (source) {
        loadSource(game, source);
      }
      game.game_init();
      checkExecutor(game);
      uploadGraphics(game, runtime);
      const initialized = performance.now();
      smoke = !!data.smoke;
      const sample = new Float32Array(
        runtime.memory.buffer,
        runtime.runtime_sample(),
        16000,
      ).slice();
      const output = frame();
      startup = {
        fetchMs: fetched - start,
        compileMs: compiled - fetched,
        instantiateMs: instantiated - compiled,
        runtimeInitMs: runtimeInitialized - instantiated,
        gameInitMs: initialized - runtimeInitialized,
        firstFrameMs: performance.now() - initialized,
        totalMs: performance.now() - start + (executor?.cache.prepareMs || 0),
        executorCache: executor?.cache || { enabled: false, hit: false },
      };
      self.postMessage(
        { type: "ready", ...output, startup, memory: memoryReport(), sample: sample.buffer },
        [output.pixels, sample.buffer],
      );
    } else if (data.type === "step") {
      if (!game || !Number.isInteger(data.steps) || data.steps < 1 || data.steps > 5) {
        throw new Error("Invalid step request.");
      }
      let output;
      for (let i = 0; i < data.steps && (!smoke || lastTick < 120); i++) {
        const buttons = smoke ? (lastTick < 60 ? 2 : lastTick === 60 ? 16 : 0) : data.input.buttons;
        game.game_update(
          buttons,
          smoke ? 0 : Number(data.input.pointer),
          smoke ? 0 : data.input.x,
          smoke ? 0 : data.input.y,
        );
        output = frame();
      }
      if (output) {
        self.postMessage({ type: "frame", ...output }, [output.pixels]);
      }
    } else if (data.type === "benchmark") {
      if (
        !game ||
        !Array.isArray(data.masks) ||
        !data.masks.length ||
        data.masks.length > 10000 ||
        data.masks.some((mask) => !Number.isInteger(mask) || mask < 0 || mask > 31)
      ) {
        throw new Error("Invalid benchmark replay.");
      }
      const timings = [],
        traces = [];
      let peakLinear = game.memory.buffer.byteLength,
        peakHeap = 0;
      for (let pass = 0; pass < 7; pass++) {
        game.game_init();
        checkExecutor(game);
        for (const mask of data.masks) {
          const t0 = performance.now();
          game.game_update(mask, 0, 0, 0);
          const t1 = performance.now();
          const drawing = submit();
          const { record } = drawing;
          const t2 = performance.now();
          rasterize(drawing);
          const t3 = performance.now();
          new Uint8Array(
            runtime.memory.buffer,
            runtime.runtime_pixels(),
            drawing.width * drawing.height * 4,
          ).slice();
          const t4 = performance.now();
          if (pass >= 2) {
            timings.push([t1 - t0, t2 - t1, t3 - t2, t4 - t3]);
          }
          if (pass === 2) {
            traces.push({ hash: runtime.runtime_hash() >>> 0, sounds: record.sounds });
          }
          peakLinear = Math.max(peakLinear, game.memory.buffer.byteLength);
          peakHeap = Math.max(peakHeap, game.game_heap_peak?.() || 0);
        }
      }
      self.postMessage({
        type: "benchmark",
        startup,
        memory: { ...memoryReport(), peakLinear, peakHeap: game.game_heap_peak ? peakHeap : null },
        timings,
        traces,
      });
    } else {
      throw new Error("Unknown player request.");
    }
  } catch (error) {
    self.postMessage({ type: "error", error: error.message || String(error) });
  }
};

function memoryReport() {
  return {
    initialLinear: initialMemory,
    currentLinear: game.memory.buffer.byteLength,
    runtimeLinear: runtime.memory.buffer.byteLength,
    heapBytes: game.game_heap_bytes?.() ?? null,
    heapPeak: game.game_heap_peak?.() ?? null,
  };
}

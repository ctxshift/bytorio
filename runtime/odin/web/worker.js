import { resourceSchema as audioLimits } from "./constants.js";
import {
  inspectGuest,
  checkExecutor,
  loadSource,
  uploadGraphics,
  submitDrawing,
  rasterizeDrawing,
  FRAME_BYTES,
  configureResources,
  submitResources,
  deliverResources,
} from "./policy.js";
import { decodeCartridge } from "./cartridge.js";

let game, runtime;
let smoke = false;
let lastTick = 0;
const imports = { env: { sin: Math.sin } };
let startup;
let resourceTrace = false;
let initialMemory;
let executorRequest;
const audioTransfers = Array.from({ length: audioLimits.maxAudioTransfers }, () => ({
  buffer: null,
  busy: false,
  capacity: 0,
}));
let pendingAudioBytes = 0;
function drainAudio() {
  if (!runtime?.runtime_audio_enabled?.()) {
    return;
  }
  for (let id = 0; id < audioTransfers.length; id++) {
    const slot = audioTransfers[id];
    if (slot.busy) {
      continue;
    }
    const bytes = pendingAudioBytes || runtime.runtime_audio_export();
    if (!bytes) {
      break;
    }
    if (bytes < 0) {
      throw new Error("Audio packet exceeds transfer capacity.");
    }
    pendingAudioBytes = bytes;
    // One aggregate credit budget, including buffers currently owned by the
    // worklet. Discard oversized idle buffers on this producer, never in process().
    let retained = 0;
    for (const other of audioTransfers) {
      if (!other.busy && other !== slot) {
        other.buffer = null;
        other.capacity = 0;
      }
      retained += other.capacity;
    }
    const capacity = Math.max(slot.capacity, bytes);
    if (retained - slot.capacity + capacity > audioLimits.maxAudioPacketBytes) {
      return;
    }
    if (!slot.buffer || slot.buffer.byteLength < bytes) {
      slot.buffer = new ArrayBuffer(bytes);
      slot.capacity = bytes;
    }
    new Uint8Array(slot.buffer, 0, bytes).set(
      new Uint8Array(runtime.memory.buffer, runtime.runtime_audio_packet(), bytes),
    );
    self.postMessage({ type: "audio-packet", id, bytes, buffer: slot.buffer }, [slot.buffer]);
    slot.buffer = null;
    slot.busy = true;
    pendingAudioBytes = 0;
  }
}
function requestExecutor() {
  return new Promise((resolve) => {
    executorRequest = resolve;
    self.postMessage({ type: "executor" });
  });
}

async function fetchBytes(url, limit = 1024 * 1024) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Could not load ${new URL(url, location.href).pathname}.`);
  }
  const reader = response.body.getReader(),
    chunks = [];
  let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) {
        break;
      }
      size += value.byteLength;
      if (size > limit) {
        await reader.cancel();
        throw new Error("Module or PNG exceeds prototype size limit.");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const part of chunks) {
    bytes.set(part, offset);
    offset += part.length;
  }
  return bytes.buffer;
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
    audioEnabled: !!runtime.runtime_audio_enabled?.(),
    spriteX: record.spriteX,
    spriteY: record.spriteY,
    x: record.x,
    y: record.y,
    hash: runtime.runtime_hash() >>> 0,
    ...(resourceTrace
      ? {
          resourceHash: runtime.runtime_resource_hash() >>> 0,
          resourceBytes: runtime.runtime_resource_bytes() >>> 0,
        }
      : {}),
  };
}

self.onmessage = async ({ data }) => {
  try {
    if (data.type === "audio-recycle") {
      const slot = audioTransfers[data.id];
      if (!slot || !slot.busy) {
        throw new Error("Invalid recycled audio transfer.");
      }
      slot.buffer = data.buffer;
      slot.busy = false;
      drainAudio();
      return;
    }
    if (data.type === "audio-feedback") {
      new Uint8Array(
        runtime.memory.buffer,
        runtime.runtime_audio_feedback_pointer(),
        data.bytes,
      ).set(new Uint8Array(data.buffer, 0, data.bytes));
      if (runtime.runtime_audio_feedback(data.bytes) !== 1) {
        throw new Error("Invalid audio feedback.");
      }
      self.postMessage({ type: "audio-feedback-recycle", id: data.id, buffer: data.buffer }, [
        data.buffer,
      ]);
      drainAudio();
      return;
    }
    if (data.type === "executor" && executorRequest) {
      const resolve = executorRequest;
      executorRequest = null;
      resolve(data.executor);
      return;
    }
    if (data.type === "load") {
      resourceTrace = !!data.resourceTrace;
      const url = new URL(data.gameUrl, location.href);
      if (url.origin !== location.origin) {
        throw new Error("Game URL must use the player origin.");
      }
      const start = performance.now();
      const isSource = url.pathname.endsWith(".luau");
      const isPNG = !!data.cartridge || url.pathname.toLowerCase().endsWith(".png");
      const [input, runtimeBytes] = await Promise.all([
        data.cartridge || fetchBytes(url, isPNG ? 2 * 1024 * 1024 : 1024 * 1024),
        fetchBytes("./runtime.wasm"),
      ]);
      runtime = (await WebAssembly.instantiate(runtimeBytes, imports)).instance.exports;
      const cartridge = isPNG ? decodeCartridge(runtime, input) : null;
      let executor = isSource ? data.executor : null;
      let gameBytes = cartridge ? cartridge.code : input;
      let source = null;
      if (isSource || cartridge?.language === "luau") {
        source = gameBytes;
        executor ||= cartridge
          ? await requestExecutor()
          : { bytes: await fetchBytes("./luau-executor.wasm") };
        gameBytes = executor.bytes;
      }
      const fetched = performance.now();
      self.postMessage({ type: "executing" });
      const gameModule = inspectGuest(gameBytes, executor?.module);
      const compiled = performance.now();
      game = (await WebAssembly.instantiate(gameModule, imports)).exports;
      const instantiated = performance.now();
      initialMemory = game.memory.buffer.byteLength;
      if (game.game_abi() !== 1 || game.game_frame_size() !== FRAME_BYTES) {
        throw new Error("Unsupported game ABI or frame size.");
      }
      runtime.runtime_init();
      const runtimeInitialized = performance.now();
      game._initialize?.();
      if (cartridge && game.game_sdk_version?.() !== 256) {
        throw new Error("Cartridge SDK version does not match its metadata.");
      }
      if (source) {
        loadSource(game, source);
      }
      configureResources(game, runtime);
      game.game_init();
      checkExecutor(game);
      submitResources(game, runtime);
      if (cartridge && game.game_display_mode?.() !== cartridge.display) {
        throw new Error("Cartridge initial display does not match its metadata.");
      }
      uploadGraphics(game, runtime);
      const initialized = performance.now();
      smoke = !!data.smoke;
      const sample = new Float32Array(
        runtime.memory.buffer,
        runtime.runtime_sample(),
        16000,
      ).slice();
      const output = frame();
      drainAudio();
      startup = {
        fetchMs: fetched - start,
        compileMs: compiled - fetched,
        instantiateMs: instantiated - compiled,
        runtimeInitMs: runtimeInitialized - instantiated,
        gameInitMs: initialized - runtimeInitialized,
        firstFrameMs: performance.now() - initialized,
        // A PNG requests its executor during this interval. Loose-source loads
        // may arrive with an executor prepared before the worker's clock starts.
        totalMs: performance.now() - start + (data.executor?.cache?.prepareMs || 0),
        executorCache: executor?.cache || { enabled: false, hit: false },
      };
      self.postMessage(
        {
          type: "ready",
          ...output,
          title: cartridge?.title,
          startup,
          memory: memoryReport(),
          sample: sample.buffer,
        },
        [output.pixels, sample.buffer],
      );
    } else if (data.type === "step") {
      if (!game || !Number.isInteger(data.steps) || data.steps < 1 || data.steps > 5) {
        throw new Error("Invalid step request.");
      }
      let output;
      for (let i = 0; i < data.steps && (!smoke || lastTick < 120); i++) {
        const buttons = smoke ? (lastTick < 60 ? 2 : lastTick === 60 ? 16 : 0) : data.input.buttons;
        deliverResources(game, runtime);
        game.game_update(
          buttons,
          smoke ? 0 : Number(data.input.pointer),
          smoke ? 0 : data.input.x,
          smoke ? 0 : data.input.y,
        );
        checkExecutor(game);
        submitResources(game, runtime);
        drainAudio();
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
      let resourceBaseline = [0, 0, 0];
      for (let pass = 0; pass < 7; pass++) {
        configureResources(game, runtime);
        game.game_init();
        checkExecutor(game);
        submitResources(game, runtime);
        resourceBaseline = [0, 1, 2].map((index) =>
          Number(runtime.runtime_resource_stat?.(index) || 0),
        );
        for (const mask of data.masks) {
          const t0 = performance.now();
          deliverResources(game, runtime);
          game.game_update(mask, 0, 0, 0);
          checkExecutor(game);
          submitResources(game, runtime);
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
        resourceStats: {
          packetBytes: Number(runtime.runtime_resource_stat?.(0) || 0) - resourceBaseline[0],
          hostCopyBytes: Number(runtime.runtime_resource_stat?.(1) || 0) - resourceBaseline[1],
          pixelWork: Number(runtime.runtime_resource_stat?.(2) || 0) - resourceBaseline[2],
          peakResourceBytes: Number(runtime.runtime_resource_stat?.(3) || 0),
        },
      });
    } else {
      throw new Error("Unknown player request.");
    }
  } catch (error) {
    runtime?.runtime_resource_close?.();
    game = runtime = null;
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

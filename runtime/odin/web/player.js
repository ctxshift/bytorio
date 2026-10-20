import { PREVIEW_SAMPLE_RATE, resourceSchema as audioLimits } from "./constants.js";
import { prepareExecutor } from "./executor-cache.js";
import { normalizeGraphics } from "./gpu.js";
import * as controls from "./constants.js";
const canvas = document.getElementById("canvas");
const display = canvas.getContext("2d", { alpha: false });
const button = document.getElementById("start");
const status = document.getElementById("status");
const parameters = new URLSearchParams(location.search);
const smoke = parameters.has("smoke");
let statsStarted = performance.now();
let statsFrames = 0;
let statsUploads = 0;
const mib = (bytes) => (bytes / 1048576).toFixed(2);
let graphics = { backend: "cpu", ssaa: "off", pixelSnap: false, smoothPan: false };
try {
  graphics = normalizeGraphics(JSON.parse(localStorage.getItem("graphics-v1") || "{}"));
} catch {
  /* Storage may be unavailable or contain old/invalid preferences. */
}
let graphicsError = "";
try {
  const selected =
    parameters.get("renderer") === "cpu" ? { ...graphics, residentMeshes: false } : graphics;
  graphics = normalizeGraphics({
    ...selected,
    backend: parameters.get("renderer") || selected.backend,
    ssaa: parameters.get("ssaa") || selected.ssaa,
    pixelSnap: parameters.has("pixel-snap") || selected.pixelSnap,
    smoothPan: parameters.has("smooth-pan") || selected.smoothPan,
    residentMeshes: parameters.has("gpu-meshes") || selected.residentMeshes,
  });
} catch (error) {
  graphicsError = error.message;
}
const graphicsBackend = document.getElementById("graphics-backend");
const graphicsSsaa = document.getElementById("graphics-ssaa");
const graphicsSnap = document.getElementById("graphics-snap");
const graphicsSmooth = document.getElementById("graphics-smooth");
const graphicsResident = document.getElementById("graphics-resident");
graphicsBackend.value = graphics.backend;
graphicsSsaa.value = graphics.ssaa;
graphicsSnap.checked = graphics.pixelSnap;
graphicsSmooth.checked = graphics.smoothPan;
graphicsResident.checked = graphics.residentMeshes;
const syncGraphicsControls = () => {
  const cpu = graphicsBackend.value === "cpu";
  graphicsResident.disabled = cpu;
  if (cpu) {
    graphicsResident.checked = false;
  }
};
graphicsBackend.addEventListener("change", syncGraphicsControls);
syncGraphicsControls();
document.getElementById("graphics-apply").addEventListener("click", () => {
  graphics = normalizeGraphics({
    backend: graphicsBackend.value,
    ssaa: graphicsSsaa.value,
    pixelSnap: graphicsSnap.checked,
    smoothPan: graphicsSmooth.checked,
    residentMeshes: graphicsResident.checked,
  });
  try {
    localStorage.setItem("graphics-v1", JSON.stringify(graphics));
  } catch {
    /* Session settings still apply. */
  }
  load(started).catch((error) => fail(error.message));
});
const keys = new Set();
const pointer = { pointer: false, x: 0, y: 0 };
let worker,
  watchdog,
  pending = false,
  started = false,
  autoStart = false;
let selectedCartridge = null;
let mixerNode = null;
let mixerLoading = null;
let mixerGeneration = 0;
const mixerPackets = [];

async function ensureMixer() {
  if (mixerNode || !globalThis.playerAudio.lowEnabled) {
    return;
  }
  if (mixerLoading) {
    return mixerLoading;
  }
  const current = generation;
  mixerLoading = (async () => {
    const context = globalThis.playerAudio.context;
    await context.audioWorklet.addModule("./audio-worklet.js");
    const response = await fetch("./audio.wasm");
    if (!response.ok) {
      throw new Error("Cannot load shared audio mixer.");
    }
    const module = await WebAssembly.compile(await response.arrayBuffer());
    if (current !== generation || !worker || !globalThis.playerStatus.ready) {
      return;
    }
    const node = new AudioWorkletNode(context, "console-pcm-mixer", {
      numberOfInputs: 0,
      numberOfOutputs: 1,
      outputChannelCount: [2],
      processorOptions: { module },
    });
    mixerNode = node;
    mixerGeneration = current;
    node.port.onmessage = ({ data }) => {
      if (data.type === "closed") {
        node.port.close();
        return;
      }
      if (current !== generation) {
        return;
      }
      if (data.type === "error") {
        fail(data.error);
      } else if (data.type === "recycle") {
        worker.postMessage({ type: "audio-recycle", id: data.id, buffer: data.buffer }, [
          data.buffer,
        ]);
      } else if (data.type === "feedback") {
        const view = new DataView(data.buffer, 0, data.bytes);
        const wide = (at) => view.getUint32(at, true) + view.getUint32(at + 4, true) * 2 ** 32;
        globalThis.playerAudio.mixerStatus = {
          frame: wide(16),
          epoch: view.getUint32(12, true),
          lateEvents: wide(32),
          underrunFrames: wide(40),
          rejectedWrites: wide(48),
          completed: wide(56),
          deviceRate: context.sampleRate,
          leadFrames: audioLimits.audioLeadFrames,
          baseLatency: context.baseLatency,
          outputLatency: context.outputLatency ?? null,
        };
        worker.postMessage(
          { type: "audio-feedback", id: data.id, buffer: data.buffer, bytes: data.bytes },
          [data.buffer],
        );
      }
    };
    node.onprocessorerror = () => {
      if (current === generation && mixerNode === node) {
        fail("AudioWorklet mixer failed.");
      }
    };
    for (const packet of mixerPackets.splice(0)) {
      node.port.postMessage({ ...packet, type: "packet" }, [packet.buffer]);
    }
    node.connect(context.destination);
  })();
  try {
    await mixerLoading;
  } finally {
    mixerLoading = null;
  }
}

function closeMixer() {
  mixerGeneration = 0;
  if (mixerNode) {
    mixerNode.port.postMessage({ type: "close" });
    mixerNode.disconnect();
    mixerNode = null;
  }
  mixerPackets.length = 0;
  globalThis.playerAudio.lowEnabled = false;
  globalThis.playerAudio.mixerStatus = null;
}
let selection = 0;
let previous = performance.now(),
  accumulator = 0,
  generation = 0,
  soundsPlayed = 0;
globalThis.playerStatus = { ready: false, error: "", ticks: 0 };

globalThis.playerAudio = {
  context: null,
  buffer: null,
  played: 0,
  ended: 0,
  peak: 0,
  source: null,
  play() {
    if (!this.buffer || this.context?.state !== "running") {
      return;
    }
    if (this.source) {
      this.source.onended = null;
      this.source.stop();
    }
    const source = this.context.createBufferSource();
    source.buffer = this.buffer;
    source.connect(this.context.destination);
    source.onended = () => {
      this.ended++;
      if (this.source === source) {
        this.source = null;
      }
    };
    source.start();
    this.source = source;
    this.played++;
  },
};

function stopOutput() {
  keys.clear();
  pointer.pointer = false;
  const audio = globalThis.playerAudio;
  if (audio.source) {
    audio.source.onended = null;
    audio.source.stop();
    audio.source = null;
  }
}

function fail(message) {
  clearTimeout(watchdog);
  worker?.terminate();
  stopOutput();
  closeMixer();
  worker = null;
  pending = started = false;
  globalThis.playerStatus = { ...globalThis.playerStatus, ready: false, error: message };
  status.textContent = message;
  button.textContent = "Restart game";
  button.disabled = false;
}

function armWatchdog(delay) {
  clearTimeout(watchdog);
  watchdog = setTimeout(() => fail("Game stopped responding. Restart to try again."), delay);
}

function maybePlay() {
  if (started && globalThis.playerStatus.sounds !== soundsPlayed) {
    globalThis.playerAudio.play();
    soundsPlayed = globalThis.playerStatus.sounds;
  }
}

async function start() {
  const audio = globalThis.playerAudio;
  if (!audio.context) {
    audio.context = new AudioContext();
  }
  await audio.context.resume();
  if (audio.context.state !== "running") {
    throw new Error("Audio could not start. Try again.");
  }
  if (globalThis.playerStatus.error) {
    load(true);
    return;
  }
  if (!globalThis.playerStatus.ready) {
    return;
  }
  if (!audio.buffer) {
    audio.buffer = audio.context.createBuffer(1, audio.samples.length, PREVIEW_SAMPLE_RATE);
    audio.buffer.copyToChannel(audio.samples, 0);
  }
  started = true;
  await ensureMixer();
  mixerNode?.port.postMessage({ type: "pause", paused: false });
  previous = performance.now();
  accumulator = 0;
  button.textContent = "Resume game";
  canvas.focus();
  maybePlay();
}

async function load(restart = false) {
  if (!display || display.isContextLost?.()) {
    fail("Display context unavailable. Restore the display and restart the game.");
    return;
  }
  const currentGeneration = ++generation;
  worker?.terminate();
  stopOutput();
  closeMixer();
  pending = started = false;
  autoStart = restart;
  soundsPlayed = 0;
  globalThis.playerAudio.buffer = null;
  globalThis.playerStatus = { ready: false, error: "", ticks: 0 };
  status.textContent = "Loading Odin player…";
  button.disabled = true;
  worker = new Worker("./worker.js", { type: "module" });
  armWatchdog(10000);
  worker.onerror = (event) => {
    event.preventDefault();
    if (currentGeneration === generation) {
      fail(event.message || "Player worker failed.");
    }
  };
  worker.onmessage = ({ data }) => {
    if (currentGeneration !== generation) {
      return;
    }
    if (data.type === "audio-packet") {
      if (mixerNode && mixerGeneration === generation) {
        mixerNode.port.postMessage({ ...data, type: "packet" }, [data.buffer]);
      } else {
        if (mixerPackets.length >= audioLimits.maxAudioTransfers) {
          fail("Initial audio schedule exceeds transfer credits.");
          return;
        }
        mixerPackets.push(data);
      }
      return;
    }
    if (data.type === "audio-feedback-recycle") {
      mixerNode?.port.postMessage({ type: "feedback-recycle", id: data.id, buffer: data.buffer }, [
        data.buffer,
      ]);
      return;
    }
    if (data.type === "executor") {
      armWatchdog(10000);
      prepareExecutor("./luau-executor.wasm")
        .then((executor) => {
          if (currentGeneration === generation) {
            worker.postMessage({ type: "executor", executor });
          }
        })
        .catch((error) => {
          if (currentGeneration === generation) {
            fail(error.message);
          }
        });
      return;
    }
    if (data.type === "executing") {
      armWatchdog(1000);
      return;
    }
    clearTimeout(watchdog);
    pending = false;
    if (data.type === "error") {
      fail(data.error);
      return;
    }
    if (data.type === "ready") {
      if (data.title) {
        document.title = data.title;
      }
      const audio = globalThis.playerAudio;
      audio.samples = new Float32Array(data.sample);
      audio.peak = audio.samples.reduce((peak, value) => Math.max(peak, Math.abs(value)), 0);
      button.disabled = false;
      button.textContent = "Start game";
    }
    if (data.type !== "ready" && data.type !== "frame") {
      fail("Invalid player response.");
      return;
    }
    if (data.audioEnabled) {
      globalThis.playerAudio.lowEnabled = true;
      if (started) {
        ensureMixer().catch((error) => fail(error.message));
      }
    }
    const imageWidth = data.presentationWidth || data.width,
      imageHeight = data.presentationHeight || data.height;
    if (canvas.width !== imageWidth || canvas.height !== imageHeight) {
      canvas.width = imageWidth;
      canvas.height = imageHeight;
      resize();
    }
    if (data.bitmap) {
      display.drawImage(data.bitmap, 0, 0);
      data.bitmap.close();
    } else {
      display.putImageData(
        new ImageData(new Uint8ClampedArray(data.pixels), imageWidth, imageHeight),
        0,
        0,
      );
    }
    const { ticks, sounds, spriteX, spriteY, x, y, hash, width, height } = data;
    if (data.metrics) {
      const now = performance.now();
      statsFrames++;
      statsUploads += data.metrics.gpuUploadBytes;
      const elapsed = now - statsStarted;
      if (elapsed >= 500 || data.type === "ready") {
        const m = data.metrics;
        document.getElementById("performance").textContent =
          `${started && elapsed >= 500 ? ((statsFrames * 1000) / elapsed).toFixed(1) : "—"} FPS delivered · render ${m.renderMs.toFixed(1)} ms\n` +
          `GPU uploads ${mib((statsUploads * 1000) / Math.max(1, elapsed))} MiB/s · mesh uploads ${m.meshUploads}\n` +
          `GPU meshes ${mib(m.gpuCacheBytes)} MiB · textures ${mib(m.gpuTextureBytes)} MiB (est.)\n` +
          `Wasm guest ${mib(m.memory.currentLinear)} MiB · runtime ${mib(m.memory.runtimeLinear)} MiB\n` +
          `Resources ${mib(m.resourceBytes)} MiB · CPU quality ${mib(m.cpuQualityBytes)} MiB (overlaps runtime)`;
        statsStarted = now;
        statsFrames = 0;
        statsUploads = 0;
      }
    }
    globalThis.playerStatus = {
      ...globalThis.playerStatus,
      ready: true,
      error: "",
      ticks,
      sounds,
      spriteX,
      spriteY,
      x,
      y,
      hash,
      width,
      height,
      smoothPresentation: data.smoothPresentation,
      presentationWidth: imageWidth,
      presentationHeight: imageHeight,
      metrics: data.metrics,
    };
    resize();
    if (data.startup) {
      globalThis.playerStatus.startup = data.startup;
    }
    if (data.graphics) {
      globalThis.playerStatus.graphics = data.graphics;
      document.getElementById("graphics-status").textContent =
        `Active renderer: ${data.graphics.effective}${data.graphics.fallback ? ` · ${data.graphics.fallback}` : ""}`;
    }
    if (graphics.smoothPan && !data.smoothPresentation) {
      document.getElementById("graphics-status").textContent =
        "Smooth pan inactive: needs an enlarged single orthographic screen batch with opaque HUD draws.";
    }
    if (data.memory) {
      globalThis.playerStatus.memory = data.memory;
    }
    status.textContent =
      globalThis.playerInstructions || "Arrows / WASD: move · Space / tap: sound";
    maybePlay();
    if (autoStart) {
      autoStart = false;
      start().catch((error) => fail(error.message));
    }
  };
  try {
    const gameUrl = parameters.get("game") || globalThis.playerCartridge || "./game.wasm";
    const executor =
      !selectedCartridge && new URL(gameUrl, location.href).pathname.endsWith(".luau")
        ? await prepareExecutor("./luau-executor.wasm")
        : null;
    if (currentGeneration !== generation) {
      return;
    }
    worker.postMessage({
      type: "load",
      gameUrl,
      smoke,
      executor,
      cartridge: selectedCartridge,
      graphics,
      presentationSize: displayPixels(),
    });
  } catch (error) {
    if (currentGeneration === generation) {
      fail(error.message || String(error));
    }
  }
}

async function openCartridge(file) {
  if (!file) {
    return;
  }
  const currentSelection = ++selection;
  if (!file.size || file.size > 2 * 1024 * 1024) {
    fail("PNG cartridge must be at most 2 MiB for the current preview.");
    return;
  }
  try {
    const bytes = await file.arrayBuffer();
    if (currentSelection !== selection) {
      return;
    }
    selectedCartridge = bytes;
    await load();
  } catch (error) {
    if (currentSelection === selection) {
      fail(error.message);
    }
  }
}
document.getElementById("cartridge").addEventListener("change", (event) => {
  const file = event.target.files[0];
  event.target.value = "";
  openCartridge(file);
});
window.addEventListener("dragover", (event) => event.preventDefault());
window.addEventListener("drop", (event) => {
  event.preventDefault();
  openCartridge(event.dataTransfer.files[0]);
});

function input() {
  let buttons = 0;
  for (const [key, mask] of [
    ["KeyA", controls.BUTTON_MOVE_LEFT],
    ["KeyD", controls.BUTTON_MOVE_RIGHT],
    ["KeyW", controls.BUTTON_MOVE_UP],
    ["KeyS", controls.BUTTON_MOVE_DOWN],
    ["ArrowLeft", controls.BUTTON_PAN_LEFT],
    ["ArrowRight", controls.BUTTON_PAN_RIGHT],
    ["ArrowUp", controls.BUTTON_PAN_UP],
    ["ArrowDown", controls.BUTTON_PAN_DOWN],
    ["KeyQ", controls.BUTTON_ROTATE_LEFT],
    ["KeyE", controls.BUTTON_ROTATE_RIGHT],
    ["KeyR", controls.BUTTON_RESET],
  ]) {
    if (keys.has(key)) {
      buttons |= mask;
    }
  }
  if (keys.has("ArrowLeft") || keys.has("KeyA")) {
    buttons |= 1;
  }
  if (keys.has("ArrowRight") || keys.has("KeyD")) {
    buttons |= 2;
  }
  if (keys.has("ArrowUp") || keys.has("KeyW")) {
    buttons |= 4;
  }
  if (keys.has("ArrowDown") || keys.has("KeyS")) {
    buttons |= 8;
  }
  if (keys.has("Space")) {
    buttons |= 16;
  }
  const pad = [...(navigator.getGamepads?.() || [])].find(
    (pad) => pad?.connected && pad.mapping === "standard",
  );
  if (pad) {
    if (pad.buttons[14]?.pressed) {
      buttons |= 1 | controls.BUTTON_MOVE_LEFT;
    }
    if (pad.buttons[15]?.pressed) {
      buttons |= 2 | controls.BUTTON_MOVE_RIGHT;
    }
    if (pad.buttons[12]?.pressed) {
      buttons |= 4 | controls.BUTTON_MOVE_UP;
    }
    if (pad.buttons[13]?.pressed) {
      buttons |= 8 | controls.BUTTON_MOVE_DOWN;
    }
    if (pad.buttons[0]?.pressed) {
      buttons |= 16;
    }
  }
  return {
    buttons,
    ...pointer,
    pointer:
      pointer.pointer &&
      pointer.x >= 0 &&
      pointer.x < canvas.width &&
      pointer.y >= 0 &&
      pointer.y < canvas.height,
  };
}

function animate(now) {
  const delta = Math.min(Math.max((now - previous) / 1000, 0), 0.1);
  previous = now;
  if (started && worker && !document.hidden && !(smoke && globalThis.playerStatus.ticks >= 120)) {
    accumulator = Math.min(accumulator + delta, 5 / 60);
    const steps = smoke ? 1 : Math.min(Math.floor(accumulator * 60), 5);
    if (!pending && steps > 0) {
      accumulator = Math.max(0, accumulator - steps / 60);
      pending = true;
      armWatchdog(1000);
      worker.postMessage({
        type: "step",
        steps,
        input: input(),
        presentationSize: displayPixels(),
      });
    }
  }
  requestAnimationFrame(animate);
}

function resetInput() {
  keys.clear();
  pointer.pointer = false;
  accumulator = 0;
}
window.addEventListener("blur", () => {
  resetInput();
  started = false;
  mixerNode?.port.postMessage({ type: "pause", paused: true });
});
document.addEventListener("visibilitychange", () => {
  resetInput();
  previous = performance.now();
  if (document.hidden) {
    started = false;
    mixerNode?.port.postMessage({ type: "pause", paused: true });
  }
});
window.addEventListener("keydown", (event) => {
  if (document.activeElement !== canvas) {
    return;
  }
  if (
    [
      "ArrowLeft",
      "ArrowRight",
      "ArrowUp",
      "ArrowDown",
      "Space",
      "KeyW",
      "KeyA",
      "KeyS",
      "KeyD",
      "KeyQ",
      "KeyE",
      "KeyR",
    ].includes(event.code)
  ) {
    event.preventDefault();
    keys.add(event.code);
  }
});
window.addEventListener("keyup", (event) => keys.delete(event.code));
function point(event) {
  const rect = canvas.getBoundingClientRect();
  pointer.x =
    ((event.clientX - rect.left) * (globalThis.playerStatus.width || canvas.width)) / rect.width;
  pointer.y =
    ((event.clientY - rect.top) * (globalThis.playerStatus.height || canvas.height)) / rect.height;
}
canvas.addEventListener("pointerdown", (event) => {
  canvas.focus();
  canvas.setPointerCapture(event.pointerId);
  point(event);
  pointer.pointer = true;
});
canvas.addEventListener("pointermove", point);
for (const name of ["pointerup", "pointercancel", "lostpointercapture"]) {
  canvas.addEventListener(name, () => {
    pointer.pointer = false;
  });
}
button.addEventListener("click", () => start().catch((error) => fail(error.message)));
function resize() {
  const full = document.fullscreenElement === document.getElementById("screen");
  const density = devicePixelRatio || 1;
  const width = globalThis.playerStatus.width || 640,
    height = globalThis.playerStatus.height || 360;
  const available = Math.min(
    ((innerWidth - (full ? 0 : 32)) * density) / width,
    ((innerHeight - (full ? 0 : 150)) * density) / height,
  );
  const scale = available >= 1 ? Math.floor(available) : Math.max(0.25, available);
  canvas.style.width = `${(width * scale) / density}px`;
  canvas.style.height = `${(height * scale) / density}px`;
}
function displayPixels() {
  const full = document.fullscreenElement === document.getElementById("screen");
  return [
    Math.max(1, Math.floor((innerWidth - (full ? 0 : 32)) * (devicePixelRatio || 1))),
    Math.max(1, Math.floor((innerHeight - (full ? 0 : 150)) * (devicePixelRatio || 1))),
  ];
}
document.getElementById("fullscreen").addEventListener("click", () =>
  document
    .getElementById("screen")
    .requestFullscreen()
    .catch((error) => {
      status.textContent = error.message;
    }),
);
document.addEventListener("fullscreenchange", resize);
canvas.addEventListener("contextlost", (event) => {
  event.preventDefault();
  fail("Display context lost. Restore the display and restart the game.");
});
window.addEventListener("resize", resize);
resize();
if (graphicsError) {
  fail(graphicsError);
} else {
  load();
}
requestAnimationFrame(animate);

import { PREVIEW_SAMPLE_RATE } from "./constants.js";
import { prepareExecutor } from "./executor-cache.js";
const canvas = document.getElementById("canvas");
const display = canvas.getContext("2d", { alpha: false });
const button = document.getElementById("start");
const status = document.getElementById("status");
const parameters = new URLSearchParams(location.search);
const smoke = parameters.has("smoke");
const keys = new Set();
const pointer = { pointer: false, x: 0, y: 0 };
let worker,
  watchdog,
  pending = false,
  started = false,
  autoStart = false;
let selectedCartridge = null;
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
  previous = performance.now();
  accumulator = 0;
  button.textContent = "Resume game";
  canvas.focus();
  maybePlay();
}

async function load(restart = false) {
  const currentGeneration = ++generation;
  worker?.terminate();
  stopOutput();
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
    if (canvas.width !== data.width || canvas.height !== data.height) {
      canvas.width = data.width;
      canvas.height = data.height;
      resize();
    }
    display.putImageData(
      new ImageData(new Uint8ClampedArray(data.pixels), data.width, data.height),
      0,
      0,
    );
    const { ticks, sounds, spriteX, spriteY, x, y, hash, width, height } = data;
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
    };
    if (data.startup) {
      globalThis.playerStatus.startup = data.startup;
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
    worker.postMessage({ type: "load", gameUrl, smoke, executor, cartridge: selectedCartridge });
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
      buttons |= 1;
    }
    if (pad.buttons[15]?.pressed) {
      buttons |= 2;
    }
    if (pad.buttons[12]?.pressed) {
      buttons |= 4;
    }
    if (pad.buttons[13]?.pressed) {
      buttons |= 8;
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
      worker.postMessage({ type: "step", steps, input: input() });
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
});
document.addEventListener("visibilitychange", () => {
  resetInput();
  previous = performance.now();
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
    ].includes(event.code)
  ) {
    event.preventDefault();
    keys.add(event.code);
  }
});
window.addEventListener("keyup", (event) => keys.delete(event.code));
function point(event) {
  const rect = canvas.getBoundingClientRect();
  pointer.x = ((event.clientX - rect.left) * canvas.width) / rect.width;
  pointer.y = ((event.clientY - rect.top) * canvas.height) / rect.height;
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
  const available = Math.min(
    ((innerWidth - (full ? 0 : 32)) * density) / canvas.width,
    ((innerHeight - (full ? 0 : 150)) * density) / canvas.height,
  );
  const scale = available >= 1 ? Math.floor(available) : Math.max(0.25, available);
  canvas.style.width = `${(canvas.width * scale) / density}px`;
  canvas.style.height = `${(canvas.height * scale) / density}px`;
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
window.addEventListener("resize", resize);
resize();
load();
requestAnimationFrame(animate);

const canvas = document.getElementById('canvas');
const display = canvas.getContext('2d', { alpha: false });
const button = document.getElementById('start');
const status = document.getElementById('status');
const parameters = new URLSearchParams(location.search);
const smoke = parameters.has('smoke');
const keys = new Set();
const pointer = { pointer: false, x: 0, y: 0 };
let worker, watchdog, pending = false, started = false, autoStart = false;
let previous = performance.now(), accumulator = 0, generation = 0, soundsPlayed = 0;
globalThis.playerStatus = { ready: false, error: '', ticks: 0 };

globalThis.playerAudio = {
  context: null, buffer: null, played: 0, ended: 0, peak: 0, source: null,
  play() {
    if (!this.buffer || this.context?.state !== 'running') return;
    if (this.source) { this.source.onended = null; this.source.stop(); }
    const source = this.context.createBufferSource();
    source.buffer = this.buffer;
    source.connect(this.context.destination);
    source.onended = () => { this.ended++; if (this.source === source) this.source = null; };
    source.start();
    this.source = source;
    this.played++;
  },
};

function fail(message) {
  clearTimeout(watchdog);
  worker?.terminate();
  worker = null;
  pending = started = false;
  globalThis.playerStatus = { ...globalThis.playerStatus, ready: false, error: message };
  status.textContent = message;
  button.textContent = 'Restart game';
  button.disabled = false;
}

function armWatchdog(delay) {
  clearTimeout(watchdog);
  watchdog = setTimeout(() => fail('Game stopped responding. Restart to try again.'), delay);
}

function maybePlay() {
  if (started && globalThis.playerStatus.sounds !== soundsPlayed) {
    globalThis.playerAudio.play();
    soundsPlayed = globalThis.playerStatus.sounds;
  }
}

async function start() {
  const audio = globalThis.playerAudio;
  if (!audio.context) audio.context = new AudioContext();
  await audio.context.resume();
  if (audio.context.state !== 'running') throw new Error('Audio could not start. Try again.');
  if (globalThis.playerStatus.error) { load(true); return; }
  if (!globalThis.playerStatus.ready) return;
  if (!audio.buffer) {
    audio.buffer = audio.context.createBuffer(1, audio.samples.length, 48000);
    audio.buffer.copyToChannel(audio.samples, 0);
  }
  started = true;
  previous = performance.now();
  accumulator = 0;
  button.textContent = 'Resume game';
  canvas.focus();
  maybePlay();
}

function load(restart = false) {
  const currentGeneration = ++generation;
  worker?.terminate();
  pending = started = false;
  autoStart = restart;
  soundsPlayed = 0;
  globalThis.playerAudio.buffer = null;
  globalThis.playerStatus = { ready: false, error: '', ticks: 0 };
  status.textContent = 'Loading Odin player…';
  button.disabled = true;
  worker = new Worker('./worker.js', { type: 'module' });
  armWatchdog(10000);
  worker.onerror = event => { event.preventDefault(); fail(event.message || 'Player worker failed.'); };
  worker.onmessage = ({ data }) => {
    if (currentGeneration !== generation) return;
    if (data.type === 'executing') { armWatchdog(1000); return; }
    clearTimeout(watchdog);
    pending = false;
    if (data.type === 'error') { fail(data.error); return; }
    if (data.type === 'ready') {
      const audio = globalThis.playerAudio;
      audio.samples = new Float32Array(data.sample);
      audio.peak = audio.samples.reduce((peak, value) => Math.max(peak, Math.abs(value)), 0);
      button.disabled = false;
      button.textContent = 'Start game';
    }
    if (data.type !== 'ready' && data.type !== 'frame') { fail('Invalid player response.'); return; }
    display.putImageData(new ImageData(new Uint8ClampedArray(data.pixels), 384, 216), 0, 0);
    const { ticks, sounds, spriteX, spriteY, x, y, hash } = data;
    globalThis.playerStatus = { ready: true, error: '', ticks, sounds, spriteX, spriteY, x, y, hash };
    status.textContent = globalThis.playerInstructions || 'Arrows / WASD: move · Space / tap: sound';
    maybePlay();
    if (autoStart) { autoStart = false; start().catch(error => fail(error.message)); }
  };
  worker.postMessage({ type: 'load', gameUrl: parameters.get('game') || './game.wasm', smoke });
}

function input() {
  let buttons = 0;
  if (keys.has('ArrowLeft') || keys.has('KeyA')) buttons |= 1;
  if (keys.has('ArrowRight') || keys.has('KeyD')) buttons |= 2;
  if (keys.has('ArrowUp') || keys.has('KeyW')) buttons |= 4;
  if (keys.has('ArrowDown') || keys.has('KeyS')) buttons |= 8;
  if (keys.has('Space')) buttons |= 16;
  const pad = [...(navigator.getGamepads?.() || [])].find(pad => pad?.connected && pad.mapping === 'standard');
  if (pad) {
    if (pad.buttons[14]?.pressed) buttons |= 1;
    if (pad.buttons[15]?.pressed) buttons |= 2;
    if (pad.buttons[12]?.pressed) buttons |= 4;
    if (pad.buttons[13]?.pressed) buttons |= 8;
    if (pad.buttons[0]?.pressed) buttons |= 16;
  }
  return { buttons, ...pointer, pointer: pointer.pointer && pointer.x >= 0 && pointer.x < 384 && pointer.y >= 0 && pointer.y < 216 };
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
      worker.postMessage({ type: 'step', steps, input: input() });
    }
  }
  requestAnimationFrame(animate);
}

function resetInput() { keys.clear(); pointer.pointer = false; accumulator = 0; }
window.addEventListener('blur', () => { resetInput(); started = false; });
document.addEventListener('visibilitychange', () => { resetInput(); previous = performance.now(); });
window.addEventListener('keydown', event => {
  if (document.activeElement !== canvas) return;
  if (['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Space', 'KeyW', 'KeyA', 'KeyS', 'KeyD'].includes(event.code)) {
    event.preventDefault(); keys.add(event.code);
  }
});
window.addEventListener('keyup', event => keys.delete(event.code));
function point(event) {
  const rect = canvas.getBoundingClientRect();
  pointer.x = (event.clientX - rect.left) * 384 / rect.width;
  pointer.y = (event.clientY - rect.top) * 216 / rect.height;
}
canvas.addEventListener('pointerdown', event => {
  canvas.focus(); canvas.setPointerCapture(event.pointerId); point(event); pointer.pointer = true;
});
canvas.addEventListener('pointermove', point);
for (const name of ['pointerup', 'pointercancel', 'lostpointercapture']) canvas.addEventListener(name, () => { pointer.pointer = false; });
button.addEventListener('click', () => start().catch(error => fail(error.message)));
function resize() {
  const available = Math.min((innerWidth - 32) / 384, (innerHeight - 150) / 216);
  const scale = available >= 1 ? Math.floor(available) : Math.max(0.25, available);
  canvas.style.width = `${384 * scale}px`;
  canvas.style.height = `${216 * scale}px`;
}
window.addEventListener('resize', resize);
resize(); load(); requestAnimationFrame(animate);

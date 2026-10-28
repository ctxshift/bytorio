import { createRuntime } from "./runtime.js";
import { normalizePlayerConfig } from "./player-config.js";
import { attachPlayerInput } from "./player-input.js";

const mounts = new WeakSet();
const styles = `
:host {display:block; color-scheme:dark; color:var(--byt-color,#e9edf3); font:14px/1.4 system-ui,sans-serif; --accent:var(--byt-accent,#80dac3)}
* {box-sizing:border-box}
.player {position:relative; width:100%; margin:auto; border:1px solid var(--byt-border,#394251); border-radius:14px; overflow:hidden; background:var(--byt-background,#161c27)}
.viewport {position:relative; display:grid; place-items:center; background:#080b12; padding:8px; overflow:hidden}
canvas {display:block; width:100%; height:auto; max-width:100%; image-rendering:pixelated; touch-action:none; outline:none; background:#080b12}
canvas:focus-visible {outline:2px solid var(--accent); outline-offset:-2px}
.toolbar {display:flex; gap:6px; align-items:center; flex-wrap:wrap; padding:8px 10px; border-top:1px solid var(--byt-border,#394251)}
.title {flex:1; min-width:5rem; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; font-weight:600; padding:0 6px}
button,summary {font:inherit; color:inherit; border:1px solid transparent; border-radius:7px; background:transparent; cursor:pointer; min-height:44px; padding:8px 12px}
button:hover,summary:hover {background:#ffffff12}
button:focus-visible,summary:focus-visible {outline:2px solid var(--accent); outline-offset:-2px}
button:disabled {opacity:.45; cursor:default}
.play {background:var(--accent); color:#101d20; font-weight:650; min-width:44px}
button svg {display:block; width:22px; height:22px; margin:auto; pointer-events:none}
.chrome-toggle {display:none}
.play:hover {filter:brightness(1.08); background:var(--accent)}
[hidden] {display:none!important}
.menu {position:relative}
.menu summary {list-style:none; display:grid; place-items:center}
.menu summary::-webkit-details-marker {display:none}
.menu-items {position:absolute; z-index:5; right:0; bottom:100%; min-width:190px; background:#202837; border:1px solid #465266; padding:6px; border-radius:10px; box-shadow:0 8px 25px #0008}
.menu-items button {display:block; width:100%; text-align:left}
.status,.instructions {margin:0; padding:0 16px 10px; color:#abb9ca; overflow-wrap:anywhere}
.status:empty,.instructions:empty {display:none}
.status[data-error] {color:#ffb4ab}
.touch-controls {position:absolute; z-index:2; bottom:max(12px,env(safe-area-inset-bottom)); left:max(12px,env(safe-area-inset-left)); right:max(12px,env(safe-area-inset-right)); display:grid; grid-template-columns:repeat(6,minmax(0,28px)) repeat(4,minmax(0,1fr)) repeat(2,minmax(0,28px)); grid-auto-rows:48px; gap:4px; pointer-events:none; user-select:none; -webkit-user-select:none; -webkit-touch-callout:none}
.touch-key {pointer-events:auto; appearance:none; -webkit-tap-highlight-color:transparent; border:1px solid #ffffff26; border-radius:16px; background:#18233138; color:#ffffff80; padding:0 4px; min-height:44px; min-width:0; font-size:22px; touch-action:none; text-shadow:0 1px 3px #0006}
.touch-key[data-control=action] {border-color:#80dac34d; color:#80dac399}
.touch-key:hover {background:#27324750}
.touch-key.pressed {background:#31455550}
.diagnostics {margin:0 10px 10px; color:#abb9ca}
pre {overflow:auto; max-height:200px; font-size:12px}
.player.fill-window {position:fixed; inset:0; z-index:1000; width:100%; height:100dvh}
.player:is(:fullscreen,.fill-window) {border:0; border-radius:0; background:#080b12}
.player:is(:fullscreen,.fill-window) .viewport {width:100%; height:100%; padding:0; container-type:size}
.player:is(:fullscreen,.fill-window) canvas {width:min(100cqw, calc(100cqh * var(--display-aspect))); height:auto}
.player:is(:fullscreen,.fill-window) .touch-key:is([data-control=up],[data-control=left],[data-control=down],[data-control=right],[data-control=action]) {transform:translateY(min(0px, calc(14px - 20cqh)))}
.player:is(:fullscreen,.fill-window) .toolbar {position:absolute; z-index:3; top:0; left:0; right:0; border:0; background:linear-gradient(#080b12bb,transparent); padding:max(4px,env(safe-area-inset-top)) max(8px,env(safe-area-inset-right)) 12px max(8px,env(safe-area-inset-left)); flex-wrap:nowrap}
.player:is(:fullscreen,.fill-window) .toolbar .play {background:#18233199; color:var(--accent)}
.player:is(:fullscreen,.fill-window)[data-running=true]:not(.chrome-open) .toolbar {display:none}
.player:is(:fullscreen,.fill-window)[data-running=true] .chrome-toggle {display:block; position:absolute; z-index:4; top:max(4px,env(safe-area-inset-top)); right:max(8px,env(safe-area-inset-right)); background:#18233170; color:#ffffffb0}
.player:is(:fullscreen,.fill-window)[data-running=true] .toolbar {padding-right:60px}
.player:is(:fullscreen,.fill-window) .menu-items {top:100%; bottom:auto}
.player:is(:fullscreen,.fill-window) .status {position:absolute; top:70px; left:10%; right:10%; text-align:center; background:#080b12bb; border-radius:8px; padding:8px; pointer-events:none}
.player:is(:fullscreen,.fill-window) .instructions {display:none}
.player:is(:fullscreen,.fill-window) .diagnostics {position:absolute; top:100px; background:#080b12dd; z-index:4}
@media(max-width:480px) {.toolbar {gap:0; padding:4px}.toolbar button {padding:8px}.title {font-size:12px}.viewport {padding:4px}}
@media(max-width:600px) {.player:is(:fullscreen,.fill-window) .title {display:none}.player:is(:fullscreen,.fill-window) .toolbar {justify-content:space-between; font-size:12px}}
@media(prefers-reduced-motion:no-preference) {button {transition:background-color .1s}}
`;

const icons = {
  play: '<path d="m8 5 11 7-11 7z"/>',
  pause: '<path d="M8 5v14M16 5v14"/>',
  volume: '<path d="M11 5 6 9H3v6h3l5 4zM15 8a6 6 0 0 1 0 8M18 5a10 10 0 0 1 0 14"/>',
  muted: '<path d="M11 5 6 9H3v6h3l5 4zM16 9l6 6m0-6-6 6"/>',
  expand: '<path d="M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5"/>',
  restore: '<path d="M3 8h5V3m8 0v5h5M8 21v-5H3m13 5v-5h5"/>',
  fullscreen: '<path d="M9 3H3v6m0-6 7 7m5-7h6v6m0-6-7 7M3 15v6h6m-6 0 7-7m11 1v6h-6m6 0-7-7"/>',
  controls: '<path d="M4 6h16M4 12h16M4 18h16M8 3v6m8 0v6m-6 0v6"/>',
};

function buttonIcon(button, icon, label) {
  if (button.dataset.icon !== icon) {
    button.innerHTML = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${icons[icon]}</svg>`;
    button.dataset.icon = icon;
  }
  button.setAttribute("aria-label", label);
  button.title = label;
}

// UI state and DOM belong to this mount; game execution is exclusively public runtime calls.
export function mountPlayer(
  element,
  {
    cartridge,
    title,
    instructions,
    controls,
    diagnostics = false,
    toolbar = true,
    fillWindow = false,
    graphics,
    frameRate = 60,
    audioContext,
  } = {},
) {
  if (!element || typeof element.append !== "function" || mounts.has(element)) {
    throw new TypeError("Supply an unmounted host element");
  }
  if (typeof toolbar !== "boolean") {
    throw new TypeError("Toolbar must be boolean");
  }
  if (typeof fillWindow !== "boolean") {
    throw new TypeError("Fill window must be boolean");
  }
  const config = normalizePlayerConfig({
    ...(title === undefined ? {} : { title }),
    ...(instructions === undefined ? {} : { instructions }),
    ...(controls === undefined ? {} : { controls }),
    diagnostics,
  });
  const document = element.ownerDocument;
  const container = document.createElement("div");
  const root = container.attachShadow({ mode: "open" });
  root.innerHTML = `<style>${styles}</style>
<section class="player" part="player" aria-label="Game player">
  <button class="chrome-toggle" type="button" aria-expanded="false"></button>
  <div class="viewport" part="viewport"><canvas width="640" height="360" tabindex="0" aria-label="Game display" part="canvas"></canvas>
    <div class="touch-controls" part="controls" role="group" aria-label="On-screen controls"></div>
  </div>
  <div class="toolbar" part="toolbar" role="group" aria-label="Playback controls">
    <button class="play" type="button">Play</button><span class="title"></span>
    <button class="mute" type="button" aria-pressed="false">Mute</button>
    <button class="fill" type="button" aria-pressed="false">Fill window</button>
    <details class="menu"><summary aria-label="More player options">•••</summary><div class="menu-items">
      <button class="restart" type="button">Restart game</button><button class="open" type="button">Open cartridge…</button>
      <button class="fullscreen" type="button">Fullscreen</button>
    </div></details>
  </div>
  <p class="status" role="status" aria-live="polite"></p><p class="instructions"></p>
  <input class="file" type="file" accept=".png,image/png" hidden>
  <details class="diagnostics"><summary>Diagnostics</summary><pre></pre></details>
</section>`;
  const find = (selector) => root.querySelector(selector);
  const canvas = find("canvas");
  const region = find(".player");
  const touch = find(".touch-controls");
  const status = find(".status");
  const play = find(".play");
  const mute = find(".mute");
  const fullscreen = find(".fullscreen");
  const fill = find(".fill");
  const chromeToggle = find(".chrome-toggle");
  chromeToggle.hidden = !toolbar;
  buttonIcon(chromeToggle, "controls", "Show player controls");
  buttonIcon(fullscreen, "fullscreen", "Fullscreen");
  function setFillWindow(value) {
    region.classList.toggle("fill-window", value);
    buttonIcon(fill, value ? "restore" : "expand", value ? "Exit fill window" : "Fill window");
    fill.setAttribute("aria-pressed", String(value));
  }
  setFillWindow(fillWindow);
  const details = find(".diagnostics");
  find(".toolbar").hidden = !toolbar;
  find(".instructions").textContent = config.instructions;
  details.hidden = !config.diagnostics;
  fullscreen.hidden = !region.requestFullscreen;
  for (const item of config.controls.layout) {
    const control = document.createElement("button");
    control.type = "button";
    control.className = "touch-key";
    control.dataset.control = item.id;
    control.textContent = item.symbol;
    control.setAttribute("aria-label", item.label);
    control.setAttribute("aria-pressed", "false");
    control.style.gridColumn = `${item.column} / span ${item.columns}`;
    control.style.gridRow = `${item.row} / span ${item.rows}`;
    touch.append(control);
  }
  element.append(container);
  let runtime;
  try {
    runtime = createRuntime({
      canvas,
      graphics,
      frameRate,
      diagnostics: config.diagnostics,
      audioContext,
    });
  } catch (error) {
    container.remove();
    throw error;
  }
  mounts.add(element);
  const detachInput = attachPlayerInput({
    runtime,
    canvas,
    controls: touch,
    config: config.controls,
  });
  const abort = new AbortController();
  const signal = abort.signal;
  const listen = (element, name, callback) => element.addEventListener(name, callback, { signal });
  let disposed = false;
  let disposal;
  function showError(error) {
    if (disposed || error.name === "AbortError") {
      return;
    }
    status.textContent = error.message || String(error);
    status.dataset.error = "true";
  }
  function reflect(state) {
    const loading = state.state === "loading";
    const failed = state.state === "failed";
    play.disabled = loading || (!state.ready && !failed);
    region.dataset.running = String(state.state === "running");
    buttonIcon(
      play,
      state.state === "running" ? "pause" : "play",
      loading
        ? "Loading game"
        : failed
          ? "Retry game"
          : state.state === "running"
            ? "Pause game"
            : "Play game",
    );
    find(".title").textContent = title ?? state.title ?? config.title;
    find(".restart").disabled = !state.ready;
    mute.setAttribute("aria-pressed", String(state.audio.muted));
    buttonIcon(mute, state.audio.muted ? "muted" : "volume", state.audio.muted ? "Unmute" : "Mute");
    status.toggleAttribute("data-error", failed);
    status.textContent = failed
      ? state.error
      : loading
        ? "Loading game…"
        : state.state === "paused"
          ? "Paused"
          : state.state === "idle"
            ? "Open a PNG cartridge to begin."
            : "";
    canvas.style.imageRendering = state.smoothPresentation ? "auto" : "pixelated";
    canvas.style.setProperty("--display-aspect", String(canvas.width / canvas.height));
    if (config.diagnostics && details.open) {
      find("pre").textContent = JSON.stringify(
        {
          state: state.state,
          ticks: state.ticks,
          renderedTicks: state.renderedTicks,
          graphics: state.graphics,
          metrics: state.metrics,
          audio: state.audio,
        },
        null,
        2,
      );
    }
  }
  const unsubscribers = [
    runtime.on("state", reflect),
    runtime.on("frame", reflect),
    runtime.on("error", reflect),
    runtime.on("audio", reflect),
    runtime.on("progress", (state) => {
      const { received, total } = state.progress;
      status.textContent = total
        ? `Loading game… ${Math.floor((received * 100) / total)}%`
        : `Loading game… ${(received / 1048576).toFixed(1)} MiB`;
    }),
  ];
  reflect(runtime.getSnapshot());
  listen(play, "click", () => {
    if (runtime.state === "running") {
      runtime.pause();
    } else if (runtime.state === "failed") {
      runtime
        .restart()
        .then(() => runtime.play())
        .catch(showError);
    } else {
      runtime
        .play()
        .then(() => {
          if (!runtime.getSnapshot().textEditing) {
            canvas.focus({ preventScroll: true });
          }
        })
        .catch(showError);
    }
  });
  listen(mute, "click", () => runtime.setMuted(!runtime.getSnapshot().audio.muted));
  listen(chromeToggle, "click", () => {
    const open = region.classList.toggle("chrome-open");
    chromeToggle.setAttribute("aria-expanded", String(open));
    buttonIcon(chromeToggle, "controls", open ? "Hide player controls" : "Show player controls");
  });
  listen(fill, "click", () => setFillWindow(!region.classList.contains("fill-window")));
  listen(region, "keydown", (event) => {
    if (event.key === "Escape" && !document.fullscreenElement) {
      setFillWindow(false);
    }
  });
  listen(fullscreen, "click", () => {
    find(".menu").open = false;
    if (document.fullscreenElement) {
      document.exitFullscreen().catch(showError);
    } else {
      region.requestFullscreen().catch(showError);
    }
  });
  listen(document, "fullscreenchange", () => {
    buttonIcon(
      fullscreen,
      root.fullscreenElement ? "restore" : "fullscreen",
      root.fullscreenElement ? "Exit fullscreen" : "Fullscreen",
    );
  });
  listen(find(".restart"), "click", () => {
    find(".menu").open = false;
    runtime.restart().catch(showError);
  });
  listen(find(".open"), "click", () => {
    find(".menu").open = false;
    find(".file").click();
  });
  listen(find(".file"), "change", (event) => {
    const file = event.target.files[0];
    event.target.value = "";
    if (file) {
      runtime.load(file).catch(showError);
    }
  });
  listen(region, "dragover", (event) => event.preventDefault());
  listen(region, "drop", (event) => {
    event.preventDefault();
    const file = event.dataTransfer.files[0];
    if (file) {
      runtime.load(file).catch(showError);
    }
  });
  const ready =
    cartridge === undefined ? Promise.resolve(runtime.getSnapshot()) : runtime.load(cartridge);
  // A mount shows failures itself; callers can also await/catch its ready promise.
  ready.catch(showError);
  return Object.freeze({
    runtime,
    element: container,
    ready,
    load: (...args) => runtime.load(...args),
    dispose() {
      if (disposal) {
        return disposal;
      }
      disposed = true;
      abort.abort();
      for (const unsubscribe of unsubscribers) {
        unsubscribe();
      }
      detachInput();
      disposal = runtime.dispose().finally(() => {
        container.remove();
        mounts.delete(element);
      });
      return disposal;
    },
  });
}

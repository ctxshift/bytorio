// The showcase shell adapts the existing player's keyboard input without
// changing the cartridge ABI or sharing state with the development player.
const canvas = document.querySelector("#canvas");
const screen = document.querySelector("#screen");
globalThis.playerInstructions = document.body.dataset.instructions;
if (!screen.requestFullscreen) {
  document.querySelector("#fullscreen").hidden = true;
}
const controls = document.createElement("div");
controls.className = "touch-controls";
controls.setAttribute("aria-label", "Touch game controls");
const directionPad = document.createElement("div");
directionPad.className = "touch-dpad";
controls.append(directionPad);
const held = new Map();
const keyCounts = new Map();
function key(code, pressed) {
  window.dispatchEvent(new KeyboardEvent(pressed ? "keydown" : "keyup", { code, bubbles: true }));
}
function release(pointerId) {
  const entry = held.get(pointerId);
  if (!entry) {
    return;
  }
  held.delete(pointerId);
  const count = (keyCounts.get(entry.code) || 1) - 1;
  keyCounts.set(entry.code, count);
  if (!count) {
    key(entry.code, false);
    entry.button.classList.remove("pressed");
    entry.button.setAttribute("aria-pressed", "false");
  }
}
for (const [code, label, symbol, position] of [
  ["ArrowUp", "Up", "↑", "up"],
  ["ArrowLeft", "Left", "←", "left"],
  ["ArrowDown", "Down", "↓", "down"],
  ["ArrowRight", "Right", "→", "right"],
  ["Space", document.body.dataset.action, "A", "action"],
]) {
  const button = document.createElement("button");
  button.className = `touch-key ${position}`;
  button.dataset.code = code;
  button.setAttribute("aria-label", label);
  button.setAttribute("aria-pressed", "false");
  button.textContent = position === "action" ? `${symbol} · ${label}` : symbol;
  button.addEventListener("pointerdown", (event) => {
    event.preventDefault();
    canvas.focus({ preventScroll: true });
    button.setPointerCapture(event.pointerId);
    held.set(event.pointerId, { code, button });
    keyCounts.set(code, (keyCounts.get(code) || 0) + 1);
    key(code, true);
    button.classList.add("pressed");
    button.setAttribute("aria-pressed", "true");
  });
  for (const event of ["pointerup", "pointercancel", "lostpointercapture"]) {
    button.addEventListener(event, (event) => release(event.pointerId));
  }
  button.addEventListener("contextmenu", (event) => event.preventDefault());
  // Native keyboard activation and assistive-technology click also work.
  button.addEventListener("click", (event) => {
    if (event.detail === 0) {
      canvas.focus({ preventScroll: true });
      key(code, true);
      setTimeout(() => key(code, false), 100);
    }
  });
  (position === "action" ? controls : directionPad).append(button);
}
screen.append(controls);
function reset() {
  for (const id of held.keys()) {
    release(id);
  }
}
window.addEventListener("blur", reset);
document.addEventListener("visibilitychange", reset);

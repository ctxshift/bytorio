globalThis.playerInstructions =
  "Arrows / WASD: walk · Space: talk / confirm · Battle: arrows to choose";
const codes = { ArrowLeft: 37, ArrowRight: 39, ArrowUp: 38, ArrowDown: 40, Space: 32 };
const controls = document.createElement("div");
controls.setAttribute("aria-label", "Game controls");
controls.style.cssText = "display:flex;justify-content:center;gap:8px;flex-wrap:wrap";
for (const [code, label] of [
  ["ArrowLeft", "←"],
  ["ArrowUp", "↑"],
  ["ArrowDown", "↓"],
  ["ArrowRight", "→"],
  ["Space", "Talk / confirm"],
]) {
  const button = document.createElement("button");
  button.textContent = label;
  button.setAttribute(
    "aria-label",
    code === "Space" ? "Talk or confirm" : code.replace("Arrow", "Move "),
  );
  button.style.cssText = "margin:8px 0;padding:12px 18px;touch-action:none;user-select:none";
  let held = false;
  const send = (type) => {
    const canvas = document.getElementById("canvas");
    canvas.focus();
    canvas.dispatchEvent(
      new KeyboardEvent(type, {
        key: code === "Space" ? " " : code,
        code,
        keyCode: codes[code],
        which: codes[code],
        bubbles: true,
        cancelable: true,
      }),
    );
  };
  button.onpointerdown = (event) => {
    event.preventDefault();
    button.setPointerCapture(event.pointerId);
    held = true;
    send("keydown");
  };
  for (const type of ["pointerup", "pointercancel", "lostpointercapture"]) {
    button.addEventListener(type, () => {
      if (held) {
        held = false;
        send("keyup");
      }
    });
  }
  controls.append(button);
}
document.querySelector("main").append(controls);
const back = document.createElement("a");
back.href = "./comparison.html";
back.textContent = "← Compare versions";
back.style.cssText = "display:block;color:#b2bfcc;margin:18px";
document.querySelector("main").append(back);
function fit() {
  const canvas = document.getElementById("canvas");
  const available = Math.min((innerWidth - 48) / 640, (innerHeight - 300) / 360);
  const scale = available >= 1 ? Math.floor(available) : Math.max(0.25, available);
  canvas.style.width = `${640 * scale}px`;
  canvas.style.height = `${360 * scale}px`;
  canvas.style.margin = "auto";
}
window.addEventListener("resize", fit);
fit();

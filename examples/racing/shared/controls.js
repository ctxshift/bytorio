globalThis.playerInstructions =
  "↑ / W: accelerate · ↓ / S: brake · ← → / A D: steer · Space: boost / restart";
const row = document.createElement("div");
row.style.cssText = "display:flex;gap:10px;justify-content:center;flex-wrap:wrap;touch-action:none";
for (const [label, code] of [
  ["◀", "ArrowLeft"],
  ["GAS", "ArrowUp"],
  ["BRAKE", "ArrowDown"],
  ["▶", "ArrowRight"],
  ["BOOST", "Space"],
]) {
  const button = document.createElement("button");
  button.textContent = label;
  button.style.cssText = "margin:8px 0;min-width:60px;user-select:none;touch-action:none";
  const send = (type) => window.dispatchEvent(new KeyboardEvent(type, { code, bubbles: true }));
  button.onpointerdown = (e) => {
    e.preventDefault();
    button.setPointerCapture(e.pointerId);
    document.getElementById("canvas").focus();
    send("keydown");
  };
  for (const name of ["pointerup", "pointercancel", "lostpointercapture"]) {
    button.addEventListener(name, () => send("keyup"));
  }
  row.append(button);
}
document.querySelector("main").append(row);
const back = document.createElement("a");
back.href = "./comparison.html";
back.textContent = "Choose cartridge";
back.style.cssText = "display:block;margin-top:12px;color:#f3c969";
document.querySelector("main").append(back);

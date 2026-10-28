import { player } from "./bootstrap.js";

Object.defineProperty(globalThis, "playerStatus", {
  get: () => player.runtime.getSnapshot(),
});

// The SDK fills its own viewport. Ask the embedding page to expand that viewport
// when the player toggles Fill Window, including Escape and touch auto-fill.
const region = player.element.shadowRoot.querySelector(".player");
function syncFillWindow() {
  if (parent !== window) {
    parent.postMessage(
      { type: "bytorio:fill-window", enabled: region.classList.contains("fill-window") },
      location.origin,
    );
  }
}
const observer = new MutationObserver(syncFillWindow);
observer.observe(region, { attributes: true, attributeFilter: ["class"] });
syncFillWindow();
window.addEventListener("pagehide", () => observer.disconnect(), { once: true });

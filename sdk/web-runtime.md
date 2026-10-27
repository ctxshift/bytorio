# Browser runtime

The SDK's `runtime.js` module runs a cartridge in a caller-supplied canvas. It
does not create a toolbar, install keyboard listeners, or style the page. The
default player uses this same execution layer. Serve the SDK's complete web
directory over HTTP(S); keep its relative files together. Assets resolve beside
the module, while cartridge URLs resolve against the embedding document. Game
URLs must share the host origin. The guest's import and resource sandbox still
applies.

```html
<canvas id="game" width="640" height="360"></canvas>
<button id="play">Play</button>
<script type="module">
  import { createRuntime } from "./sdk/web/runtime.js";

  const game = createRuntime({ canvas: document.querySelector("#game") });
  await game.load("./game.png");
  document.querySelector("#play").onclick = () => game.play();
  // Your input adapter owns each source; releasing one leaves the others held.
  game.setInput("custom-controls", { buttons: ["right", "action"] });
  game.setInput("custom-controls", null);
  // Await game.dispose() before removing/reusing the canvas.
</script>
```

This is a preview API, versioned with the SDK and its matching players:

- `createRuntime({ canvas, frameRate = 60, graphics = {}, diagnostics = false,
  audioContext })` reserves one canvas per session. An optional caller-owned
  AudioContext is reused and never closed by the runtime. Otherwise a session
  creates its own context on `play()` and closes it on disposal.
- `load(url | File | Blob | ArrayBuffer | ArrayBufferView, { graphics }?)`
  resolves when the initial frame is ready. Byte inputs are PNG cartridges;
  `.luau` and `.wasm` URLs are also supported for development. Replacing a load
  rejects the superseded operation with `AbortError`. A failed load can be retried.
- `play()` starts/resumes execution and audio; call it from a user gesture.
  `pause()` releases inputs and silences this session. `restart()` reloads the
  selected cartridge and resumes if it was running. `unload()` returns to idle.
- `setInput(source, { buttons, pointer } | null)` replaces one named source.
  `buttons` is an array of schema binding names or a mask from exported `buttons`
  and `buttonMask()`. `pointer` has logical `x`, `y`, optional `down`, `right`,
  and `hover` booleans. Inputs are combined across at most 64 sources; pointer
  presses outside the logical image are ignored. `clearInput()` releases all.
- `setMuted(boolean)` controls this session's gain. `setFrameRate(number |
  "native" | "uncapped")` changes presentation cadence, preserving 60 Hz updates.
- `pulseInput(buttons)` queues bindings for the next simulation update, surviving
  presentation-only frames. Use it for wheel events or accessible button activation.
- `state` and `getSnapshot()` expose immutable state. `on(type, listener)` returns
  an unsubscribe function; events are `state`, `progress`, `frame`, `audio`, and
  `error`. Listeners receive snapshots. `ticks` is the latest simulation tick;
  `renderedTicks`, image dimensions and hash describe the last presented frame.
  Enable `diagnostics` when collecting frame hashes on the GPU path.
- `dispose()` is idempotent and asynchronous. It stops callbacks, releases input,
  DOM editing overlays, workers and audio, and allows pending save writes a bounded
  opportunity to settle. It does not dispose other sessions. Blur/hidden-page
  transitions pause playback; the host decides when to resume.

Save identity/storage, native browser text editing, packaged content, Ogg/audio
streaming and execution watchdogs use the same runtime contracts as the native
player. Handle rejected operations and render an error/retry UI in a custom host.
The Worker protocol, `session.js`, and development-page globals are internal.

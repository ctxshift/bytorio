import { parentPort, workerData } from "node:worker_threads";
import { readFile } from "node:fs/promises";
import { decodeCartridge, contentImports } from "../../runtime/odin/web/cartridge.js";
import { unavailableSaveImports } from "../../runtime/odin/web/save.js";
import {
  inspectGuest,
  loadSource,
  checkExecutor,
  uploadGraphics,
  submitDrawing,
  rasterizeDrawing,
  configureResources,
  submitResources,
  deliverResources,
} from "../../runtime/odin/web/policy.js";
try {
  const imports = { env: { sin: Math.sin } };
  const bytes = await readFile(workerData.game);
  inspectGuest(bytes);
  const runtime = (await WebAssembly.instantiate(await readFile(workerData.runtime), imports))
    .instance.exports;
  decodeCartridge(runtime, workerData.cartridge);
  let game = null;
  game = (
    await WebAssembly.instantiate(bytes, {
      env: { sin: Math.sin, ...contentImports(runtime, () => game), ...unavailableSaveImports },
    })
  ).instance.exports;
  const source = workerData.source ? await readFile(workerData.source) : null;
  parentPort.postMessage({ type: "executing" });
  game._initialize?.();
  if (source) {
    loadSource(game, source);
  }
  if (game.game_command_stride() !== 32) {
    throw new Error("Unsupported SDK/ABI version");
  }
  configureResources(game, runtime);
  game.game_init();
  checkExecutor(game);
  submitResources(game, runtime);
  runtime.runtime_init();
  uploadGraphics(game, runtime);
  for (let i = 0; i < 3; i++) {
    deliverResources(game, runtime);
    game.game_update(0, 0, 0, 0);
    checkExecutor(game);
    submitResources(game, runtime);
    const drawing = submitDrawing(game, runtime);
    rasterizeDrawing(runtime, drawing);
  }
  parentPort.postMessage({ type: "checked" });
} catch (error) {
  parentPort.postMessage({ type: "error", message: error.message });
}

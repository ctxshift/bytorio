import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import {
  loadSource,
  uploadGraphics,
  submitDrawing,
  rasterizeDrawing,
} from "../../runtime/odin/web/policy.js";
const dir = "examples/rpg/build/player/web",
  imports = {
    env: {
      sin: Math.sin,
      content_size: () => 0,
      content_read: () => 0,
      save_size: () => 0,
      save_status: () => 3,
      save_read: () => 0,
      save_write: () => 3,
    },
  };
const game = (await WebAssembly.instantiate(await readFile(`${dir}/game.wasm`), imports)).instance
  .exports;
const runtime = (await WebAssembly.instantiate(await readFile(`${dir}/runtime.wasm`), imports))
  .instance.exports;
game.game_init();
runtime.runtime_init();
uploadGraphics(game, runtime);
const atlas = new Uint8Array(
  game.memory.buffer,
  game.game_assets(),
  game.game_assets_size(),
).slice();
const assetsOffset = runtime.runtime_assets();
function assets(bytes) {
  new Uint8Array(runtime.memory.buffer, assetsOffset, bytes.length).set(bytes);
  return runtime.runtime_load_graphics(bytes.length);
}
assert.equal(assets(atlas.slice(0, -1)), 0, "truncated atlas rejected");
const badInk = atlas.slice();
badInk[80] = 16;
assert.equal(assets(badInk), 0, "invalid palette index rejected");
const badFont = atlas.slice();
badFont[badFont.length - 1] = 255;
assert.equal(assets(badFont), 0, "invalid font bits rejected");
assert.equal(assets(atlas), 1);
function command(kind, x = 0, y = 0, w = 0, h = 0, offset = 0, length = 0, textSize = 0) {
  const view = new DataView(runtime.memory.buffer, runtime.runtime_batch(), 32);
  [kind, x, y, w, h, 0xffffffff, offset, length].forEach((value, i) =>
    view.setUint32(i * 4, value, true),
  );
  return runtime.runtime_render_batch(1, textSize);
}
assert.equal(command(9), 0, "unknown operation rejected");
assert.equal(command(1, 0, 0, 256, 1), 0, "sprite handle rejected");
assert.equal(command(1, 0, 0, 0, 0), 0, "zero sprite scale rejected");
assert.equal(command(1, 5000, 0, 0, 1), 0, "invalid coordinate rejected");
assert.equal(command(2, 0, 0, 0, 0, 1, 1, 1), 0, "text slice outside buffer rejected");
assert.equal(command(2, 0, 0, 0, 0, 0, 1025, 1025), 0, "oversized text rejected");
assert.equal(runtime.runtime_render_batch(16385, 0), 0, "oversized batch rejected");
assert.equal(command(1, -8, -8, 0, 1), 1, "partially clipped sprite accepted");
assert.equal(command(2, -1, -1, 0, 0, 0, 0, 0), 1, "empty text accepted");
let count;
for (const language of ["odin", "luau"]) {
  const g =
    language === "odin"
      ? game
      : (await WebAssembly.instantiate(await readFile(`${dir}/luau-executor.wasm`), imports))
          .instance.exports;
  if (language === "luau") {
    g._initialize();
    loadSource(g, await readFile(`${dir}/rpg.luau`));
    g.game_init();
  }
  runtime.runtime_init();
  uploadGraphics(g, runtime);
  const drawing = submitDrawing(g, runtime);
  rasterizeDrawing(runtime, drawing);
  assert.ok(drawing.count < 300, `${language} initial batch has fewer than 300 commands`);
  if (count !== undefined) {
    assert.equal(drawing.count, count, "both languages submit the same number of commands");
  }
  count = drawing.count;
}
console.log(`Batched drawing checks passed; initial frame: ${count} commands (previously 8,582).`);

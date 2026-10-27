import assert from "node:assert/strict";
import { mkdir, writeFile, copyFile, readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { randomUUID } from "node:crypto";
import { once } from "node:events";
import { createProject, buildProject } from "./sdk/project.mjs";
import { chromium } from "./browser-timing.mjs";
import { serve } from "./serve.mjs";

const root = resolve("build/web-runtime-verification", randomUUID());
await mkdir(root, { recursive: true });
for (const language of ["odin", "luau"]) {
  const project = resolve(root, language);
  await createProject(project, language);
  const entry = resolve(project, `src/main.${language}`);
  const source = await readFile(entry, "utf8");
  const draw = language === "odin" ? "draw :: proc() {" : "local function draw()";
  assert.ok(source.includes(draw));
  await writeFile(
    entry,
    source.replace(draw, `${draw}\n    byt.debug_position(x, y)${language === "odin" ? ";" : ""}`),
  );
  await buildProject(project);
  await copyFile(resolve(project, "build/game.png"), resolve(root, `${language}.png`));
}
await writeFile(
  resolve(root, "index.html"),
  `<!doctype html>
<title>Custom runtime host</title><link rel="icon" href="data:,">
<canvas width="640" height="360"></canvas><canvas width="640" height="360"></canvas>
<button>Play</button><script type="module">
import {createRuntime, buttons} from './luau/build/web/runtime.js';
const canvases = document.querySelectorAll('canvas');
window.sessions = [...canvases].map(canvas => createRuntime({canvas, diagnostics:true}));
window.bindings = buttons;
document.querySelector('button').onclick = () => Promise.all(sessions.map(session => session.play()));
window.ready = Promise.all(sessions.map((session, i) => session.load(i ? './luau.png' : './odin.png')));
</script>`,
);
const server = serve(root, 0);
await once(server, "listening");
const browser = await chromium.launch({
  channel: process.env.PLAYER_BROWSER_CHANNEL || "chrome",
  headless: true,
});
try {
  const page = await browser.newPage();
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto(`http://127.0.0.1:${server.address().port}/index.html`);
  await page.waitForFunction(() => !!window.ready);
  await page.evaluate(() => window.ready);
  assert.equal(await page.evaluate(() => "playerStatus" in window), false);
  await page.getByRole("button", { name: "Play", exact: true }).click();
  await page.waitForFunction(() =>
    window.sessions.every((session) => session.getSnapshot().ticks > 5),
  );
  const before = await page.evaluate(() =>
    window.sessions.map((session) => session.getSnapshot().x),
  );
  await page.evaluate(() => {
    window.sessions[0].setInput("keyboard", { buttons: ["right"] });
    window.sessions[0].setInput("touch", { buttons: ["right"] });
    window.sessions[0].setInput("keyboard", null);
  });
  await page.waitForFunction((x) => window.sessions[0].getSnapshot().x > x + 12, before[0]);
  assert.equal(await page.evaluate(() => window.sessions[1].getSnapshot().x), before[1]);
  await page.evaluate(() => window.sessions[0].clearInput());
  await page.evaluate(() =>
    window.sessions[0].setInput("pointer", { pointer: { x: 200, y: 140, down: true } }),
  );
  await page.waitForFunction(() => window.sessions[0].getSnapshot().x === 192);
  await page.evaluate(() => window.sessions[0].pause());
  const stopped = await page.evaluate(() => window.sessions[0].getSnapshot().ticks);
  await page.waitForFunction((tick) => window.sessions[1].getSnapshot().ticks > tick + 8, stopped);
  const paused = await page.evaluate(() => window.sessions[0].getSnapshot());
  assert.equal(paused.state, "paused");
  assert.ok(paused.ticks <= stopped + 6, "only an already submitted step may complete after pause");
  assert.ok(paused.renderedTicks <= paused.ticks);
  assert.equal(
    await page.evaluate(() => Object.isFrozen(window.sessions[0].getSnapshot().audio)),
    true,
  );
  const lifecycle = await page.evaluate(async () => {
    const session = window.sessions[0];
    let rejected = false;
    try {
      session.setInput("bad", { buttons: ["typo"] });
    } catch {
      rejected = true;
    }
    const first = session.load("./odin.png").catch((error) => error.name);
    await session.load("./luau.png");
    const superseded = await first;
    let failed = false;
    try {
      await session.load(new Uint8Array([1, 2, 3]));
    } catch {
      failed = session.state === "failed";
    }
    await session.load("./odin.png");
    await Promise.all([session.dispose(), session.dispose()]);
    return { rejected, superseded, failed, state: session.state };
  });
  assert.deepEqual(lifecycle, {
    rejected: true,
    superseded: "AbortError",
    failed: true,
    state: "disposed",
  });
  const secondTick = await page.evaluate(() => window.sessions[1].getSnapshot().ticks);
  await page.waitForFunction(
    (tick) => window.sessions[1].getSnapshot().ticks > tick + 5,
    secondTick,
  );
  await page.evaluate(() => window.sessions[1].dispose());
  assert.deepEqual(errors, []);
  await page.close();
} finally {
  await browser.close();
  await new Promise((done) => server.close(done));
}
console.log(
  `Public runtime passed: both languages, nested assets, independent sessions, input ownership, superseded loads, recovery and disposal. Evidence: ${root}`,
);

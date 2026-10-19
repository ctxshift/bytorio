import assert from "node:assert/strict";
import { once } from "node:events";
import { mkdir, readFile } from "node:fs/promises";
import { chromium } from "playwright";
import { serve } from "./serve.mjs";

const server = serve("build/web", 0);
await once(server, "listening");
let browser;
let page;
const failures = [];
try {
  browser = await chromium.launch({ channel: process.env.PLAYER_BROWSER_CHANNEL || undefined });
  page = await browser.newPage();
  page.on("pageerror", (error) => failures.push(error.message));
  page.on("console", (message) => {
    if (message.type() === "error") {
      failures.push(message.text());
    }
  });
  const url = `http://127.0.0.1:${server.address().port}/player.html`;
  await page.goto(url);
  await page.waitForFunction(
    () => globalThis.playerStatus?.ready || globalThis.playerStatus?.error,
    null,
    { timeout: 30000 },
  );
  assert.equal(await page.evaluate(() => globalThis.crossOriginIsolated), false);
  assert.equal(await page.evaluate(() => globalThis.playerStatus.error), "");
  await page.getByRole("button", { name: "Start game" }).click();
  await page.waitForFunction(
    () => globalThis.playerStatus.ticks > 5 && globalThis.playerAudio.played > 0,
  );
  const before = await page.evaluate(() => globalThis.playerStatus.spriteX);
  await page.keyboard.down("ArrowRight");
  await page.waitForFunction((x) => globalThis.playerStatus.spriteX > x + 5, before);
  await page.keyboard.up("ArrowRight");
  await page.keyboard.down("Space");
  await page.waitForFunction(() => globalThis.playerAudio.played >= 2);
  await page.keyboard.up("Space");

  // The already-started sample must continue on the audio graph during a main-thread stall.
  const audio = await page.evaluate(async () => {
    const audio = globalThis.playerAudio;
    audio.play(audio.buffer.getChannelData(0));
    const start = audio.context.currentTime;
    const until = performance.now() + 500;
    while (performance.now() < until) {
      /* Deliberate UI-thread stall. */
    }
    const advanced = audio.context.currentTime - start;
    const offline = new OfflineAudioContext(1, audio.buffer.length, 48000);
    const source = offline.createBufferSource();
    source.buffer = audio.buffer;
    source.connect(offline.destination);
    source.start();
    const rendered = await offline.startRendering();
    let peak = 0;
    for (const sample of rendered.getChannelData(0)) {
      peak = Math.max(peak, Math.abs(sample));
    }
    return { advanced, peak, state: audio.context.state, played: audio.played };
  });
  assert.equal(audio.state, "running");
  assert.ok(audio.advanced > 0.25, "audio clock advances during UI stall");
  assert.ok(audio.peak > 0.1 && audio.peak < 1, "offline audio contains the shared PCM sample");
  await mkdir("build/verification", { recursive: true });
  await page.screenshot({ path: "build/verification/browser.png" });

  await page.goto(`${url}?smoke`);
  await page.waitForFunction(() => globalThis.playerStatus?.ready);
  await page.getByRole("button", { name: "Start game" }).click();
  await page.waitForFunction(() => globalThis.playerStatus.ticks === 120);
  const smoke = await page.evaluate(() => globalThis.playerStatus);
  assert.equal(smoke.error, "");
  assert.equal(smoke.sounds, 2);
  if (process.env.PLAYER_NATIVE_REPORT) {
    const native = JSON.parse(
      (await readFile(process.env.PLAYER_NATIVE_REPORT, "utf8")).replace(/^\uFEFF/, ""),
    );
    assert.equal(smoke.hash, native.hash, "native and Wasm scripted framebuffer match");
    assert.equal(smoke.sounds, native.sounds);
  }

  // Replace only the preloaded source bytes, exercising the real Wasm compiler/VM and error UI.
  const packagedSource = await readFile("build/web/player.data");
  assert.deepEqual(
    packagedSource,
    await readFile("examples/hello/main.luau"),
    "web package contains the shared example source",
  );
  const dataLength = packagedSource.length;
  for (const [source, expected, start] of [
    ["return {", "main.luau"],
    ["error('browser error fixture')", "browser error fixture"],
    ["while true do end", "time limit"],
    ["buffer.create(16 * 1024 * 1024)", "memory"],
    [
      "return {init=function() end, update=function() error('callback error fixture') end, draw=function() end}",
      "callback error fixture",
      true,
    ],
  ]) {
    assert.ok(source.length <= dataLength);
    const failurePage = await browser.newPage();
    const messages = [];
    failurePage.on("console", (message) => messages.push(message.text()));
    failurePage.on("pageerror", (error) => messages.push(error.message));
    try {
      await failurePage.route("**/player.data", (route) =>
        route.fulfill({
          contentType: "application/octet-stream",
          body: Buffer.from(source.padEnd(dataLength, " ")),
        }),
      );
      await failurePage.goto(url);
      if (start) {
        await failurePage.waitForFunction(() => globalThis.playerStatus?.ready);
        await failurePage.getByRole("button", { name: "Start game" }).click();
      }
      await failurePage.waitForFunction(() => !!globalThis.playerStatus?.error, null, {
        timeout: 10000,
      });
      const diagnostic = await failurePage.evaluate(() => globalThis.playerStatus.error);
      assert.ok(diagnostic.includes(expected), `expected ${expected}, received ${diagnostic}`);
      const visible = await failurePage.locator("#status").textContent();
      assert.ok(visible.includes(expected), `expected visible ${expected}, received ${visible}`);
    } catch (error) {
      console.error(
        JSON.stringify({
          expected,
          messages,
          state: await failurePage.evaluate(() => ({
            status: globalThis.playerStatus,
            visible: document.getElementById("status").textContent,
          })),
        }),
      );
      throw error;
    } finally {
      await failurePage.close();
    }
  }
  assert.deepEqual(failures, []);
  console.log(
    JSON.stringify({
      browser: browser.version(),
      smoke,
      audio,
      errorFixtures: 5,
      crossOriginIsolationRequired: false,
    }),
  );
} catch (error) {
  console.error(
    JSON.stringify({
      failures,
      status: await page?.evaluate(() => globalThis.playerStatus).catch(() => null),
    }),
  );
  throw error;
} finally {
  await browser?.close();
  await new Promise((resolve) => server.close(resolve));
}

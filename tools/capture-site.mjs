import { chromium } from "playwright";
import { resolve } from "node:path";
import { once } from "node:events";
import { serveSite } from "./serve-site.mjs";
import { games } from "../site/catalog.mjs";
import { bindPlayer } from "./browser-player.mjs";
import { repo } from "./toolchain.mjs";

const server = serveSite({ port: 0 });
await once(server, "listening");
const browser = await chromium.launch({ channel: process.env.PLAYER_BROWSER_CHANNEL || undefined });
try {
  for (const game of games) {
    const page = await browser.newPage({
      viewport: { width: 960, height: 540 },
      deviceScaleFactor: 1,
    });
    await page.goto(
      `http://127.0.0.1:${server.address().port}/games/${game.id}/player.html?game=./${game.cartridge}-luau.png&renderer=cpu&ssaa=off&fill-window`,
    );
    await bindPlayer(page);
    await page.waitForFunction(() => globalThis.hostedPlayer.runtime.getSnapshot().ready, null, {
      timeout: 60000,
    });
    await page.getByRole("button", { name: "Play game", exact: true }).click();
    await page.locator("canvas").focus();
    if (game.id === "willow-junction") {
      await page.keyboard.press("ArrowLeft", { delay: 120 });
    }
    await page.keyboard.press("Space", { delay: 120 });
    await page.waitForFunction(() => globalThis.hostedPlayer.runtime.getSnapshot().ticks > 400);
    await page
      .locator("canvas")
      .screenshot({ path: resolve(repo, "site/assets", game.id + ".png") });
    await page.close();
  }
} finally {
  await browser.close();
  await new Promise((done) => server.close(done));
}
console.log("Captured both real game screens in site/assets.");

import { chromium } from "playwright";
import { resolve } from "node:path";
import { once } from "node:events";
import { serveSite } from "./serve-site.mjs";
import { games } from "../site/catalog.mjs";
import { repo } from "./toolchain.mjs";

const server = serveSite({ port: 0 });
await once(server, "listening");
const browser = await chromium.launch({ channel: process.env.PLAYER_BROWSER_CHANNEL || undefined });
try {
  for (const game of games) {
    const page = await browser.newPage({
      viewport: { width: 900, height: 700 },
      deviceScaleFactor: 1,
    });
    await page.goto(
      `http://127.0.0.1:${server.address().port}/games/${game.id}/player.html?game=./${game.cartridge}-luau.png&renderer=cpu&ssaa=off`,
    );
    await page.waitForFunction(() => globalThis.playerStatus?.ready, null, { timeout: 60000 });
    await page.locator("#start").click();
    await page.waitForFunction(() => globalThis.playerStatus?.ticks > 240);
    if (game.id === "copper-circuit") {
      await page.keyboard.down("ArrowUp");
      await page.waitForFunction(() => globalThis.playerStatus?.ticks > 420);
      await page.keyboard.up("ArrowUp");
    }
    await page
      .locator("#canvas")
      .screenshot({ path: resolve(repo, "site/assets", `${game.id}.png`) });
    await page.close();
  }
} finally {
  await browser.close();
  await new Promise((done) => server.close(done));
}
console.log("Captured both real game screens in site/assets.");

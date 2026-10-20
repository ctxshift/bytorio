import { readFile, writeFile, copyFile, mkdir } from "node:fs/promises";
import { encodeCartridge } from "../../tools/sdk/cartridge.mjs";
import { exportPlayer } from "../../tools/player-export.mjs";
const root = process.argv[2] || "build/unified-player";
const racing = process.argv[3] === "racing";
const cartridge = racing ? "racing" : "rpg";
const assets = JSON.parse(
  await readFile(
    racing ? "build/racing/cover-assets.json" : "examples/rpg-shared/assets.json",
    "utf8",
  ),
);
const cartridges = {};
for (const language of ["luau", "odin"]) {
  cartridges[language] = encodeCartridge({
    title: assets.title || "Mossglen: The Sunleaf",
    language,
    display: racing ? [320, 180] : [640, 360],
    assets,
    code: await readFile(
      language === "luau"
        ? `build/${cartridge}/${racing ? "racing" : "batched"}.luau`
        : `build/${cartridge}-odin/web/game.wasm`,
    ),
  });
}
for (const platform of ["web", "native"]) {
  const target = `${root}/${platform}`,
    source = `build/${cartridge}-odin/${platform}`;
  await mkdir(`${target}/licenses`, { recursive: true });
  for (const language of ["luau", "odin"]) {
    await writeFile(`${target}/${cartridge}-${language}.png`, cartridges[language]);
  }
  await exportPlayer({ platform, source, target, luau: true });
  await copyFile(`${source}/game.wasm`, `${target}/game.wasm`);
  await copyFile(
    racing ? "build/racing/racing.luau" : "build/rpg/batched.luau",
    `${target}/${cartridge}.luau`,
  );
}
const html = await readFile(`${root}/web/player.html`, "utf8");
await writeFile(
  `${root}/web/player.html`,
  html.replace("</body>", '<script type="module" src="./controls.js"></script>\n</body>'),
);
const controls = await readFile(`examples/${racing ? "racing" : "rpg"}-shared/controls.js`, "utf8");
await writeFile(`${root}/web/controls.js`, controls);
const launcher = await readFile(
  `examples/${racing ? "racing" : "rpg"}-shared/launcher.html`,
  "utf8",
);
await writeFile(`${root}/web/comparison.html`, launcher);
console.log(`Unified prototype staged in ${root}.`);

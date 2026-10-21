import { readFile } from "node:fs/promises";

// Package metadata owns the product identity. Runtime copies are generated.
const metadata = JSON.parse(await readFile(new URL("../package.json", import.meta.url), "utf8"));

export const branding = Object.freeze({
  name: metadata.displayName,
  command: Object.keys(metadata.bin)[0],
  website: metadata.homepage,
  playerTitle: `${metadata.displayName} player`,
  gameTitle: `${metadata.displayName} game`,
  starterTitle: `Hello, ${metadata.displayName}!`,
  starterMessage: `HELLO, ${metadata.displayName.toUpperCase()}!`,
});

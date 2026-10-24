import { mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { gzipSync } from "node:zlib";
import { branding } from "./branding.mjs";
import { repo } from "./toolchain.mjs";
import { checkVersion, digest } from "./cli/sdk-bundle.ts";

const version = checkVersion(process.argv[2] ?? "0.1.0-preview.1");
const output = resolve(repo, "build/sdk-release", version);
const assets = {};

async function collect(directory) {
  for (const entry of await readdir(resolve(repo, directory), { withFileTypes: true })) {
    const path = `${directory}/${entry.name}`;
    if (entry.isDirectory()) {
      await collect(path);
    } else if (entry.isFile() && /\.(odin|luau|json|md)$/.test(entry.name)) {
      assets[path] = await readFile(resolve(repo, path), "utf8");
    }
  }
}

await collect("sdk");
for (const entry of await readdir(repo)) {
  if (/^LICENSE(?:\.[a-zA-Z0-9]+)?$/.test(entry)) {
    assets[entry] = await readFile(resolve(repo, entry), "utf8");
  }
}
const sortedAssets = Object.fromEntries(
  Object.entries(assets).sort(([a], [b]) => a.localeCompare(b)),
);
const bytes = gzipSync(
  Buffer.from(JSON.stringify({ schema: 1, version, branding, assets: sortedAssets })),
);
const asset = `bytorio-sdk-${version}.json.gz`;
await mkdir(output, { recursive: true });
await writeFile(resolve(output, asset), bytes);
await writeFile(
  resolve(output, "sdk-release.json"),
  JSON.stringify(
    {
      schema: 1,
      version,
      cliProtocol: 1,
      asset,
      bytes: bytes.length,
      sha256: digest(bytes),
    },
    null,
    2,
  ) + "\n",
);
console.log(`SDK release assets: build/sdk-release/${version}`);

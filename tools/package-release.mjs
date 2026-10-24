import { copyFile, mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { releaseConfig } from "./release-config.mjs";
import { repo, script } from "./toolchain.mjs";

const release = releaseConfig(process.env.BYTORIO_RELEASE_TAG);
const output = resolve(repo, "build/releases", release.tag);
await mkdir(output, { recursive: true });
let source;
let files;
if (release.kind === "byt") {
  // Publish the exact binary already exercised by test:cli, not a later rebuild.
  source = resolve(repo, "build/cli");
  files = ["byt.exe", "release.json"];
} else {
  script("tools/build-sdk-release.mjs", [release.version]);
  source = resolve(repo, "build/sdk-release", release.version);
  files = [`bytorio-sdk-${release.version}.json.gz`, "sdk-release.json"];
}
for (const file of files) {
  await copyFile(resolve(source, file), resolve(output, file));
}
const notes =
  release.kind === "byt"
    ? "Windows x64 standalone scaffolding preview. Download byt.exe and release.json (SHA-256 metadata). Supports new and sdk install without Node, Bun or mise. The executable is unsigned."
    : "Versioned SDK libraries, templates, schemas and documentation for Luau and Odin. The manifest records the compressed bundle's SHA-256 and size.";
await writeFile(
  resolve(output, "release-notes.md"),
  `${notes}\n\n` +
    "Build, check, run, watch, pack and import still require the source CLI. Managed compilers and prebuilt players are not included in this preview.\n\n" +
    "[Getting started](https://bytor.io/docs/docs/getting-started.html) explains supported commands and the source fallback.\n\n" +
    `Source: tag \`${release.tag}\`. Full validation passed before these assets were packaged.\n`,
);
console.log(`Packaged ${release.tag}`);

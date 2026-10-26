import { copyFile, mkdir, readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { releaseConfig } from "./release-config.mjs";
import { repo, script } from "./toolchain.mjs";
import { requireCliHost } from "./host-platform.mjs";
import { createCliArchive } from "./cli-release-archive.mjs";

const release = releaseConfig(process.env.BYTORIO_RELEASE_TAG);
const output = resolve(repo, "build/releases", release.tag);
await mkdir(output, { recursive: true });
let source;
let files;
if (release.kind === "byt") {
  // Publish the exact binary already exercised by test:cli, not a later rebuild.
  source = resolve(repo, "build/cli");
  const host = requireCliHost();
  files = [
    [host.executable, host.cliAsset],
    ["release.json", host.cliManifest],
  ];
} else {
  script("tools/build-sdk-release.mjs", [release.version]);
  source = resolve(repo, "build/sdk-release", release.version);
  files = [[`bytorio-sdk-${release.version}.json.gz`], ["sdk-release.json"]];
}
for (const [sourceName, targetName = sourceName] of files) {
  await copyFile(resolve(source, sourceName), resolve(output, targetName));
}
if (release.kind === "byt") {
  const host = requireCliHost();
  const manifest = JSON.parse(await readFile(resolve(output, host.cliManifest), "utf8"));
  const packaged = await createCliArchive(
    release,
    manifest,
    resolve(output, host.cliAsset),
    output,
  );
  await writeFile(resolve(output, host.cliManifest), JSON.stringify(packaged, null, 2) + "\n");
}
const notes =
  release.kind === "byt"
    ? "Standalone scaffolding preview for Windows x64 and macOS Apple Silicon/Intel. Platform archives contain byt.exe on Windows or byt on Mac and support the short pinned mise entry, including older mise versions. Download byt-windows-x86_64.tar.gz, byt-macos-aarch64.tar.gz, or byt-macos-x86_64.tar.gz. Existing raw binary names remain available. Platform manifests record SHA-256 and size for both forms. Supports new and sdk install without Node, Bun or mise. Mac binaries are ad hoc signed, not notarized."
    : "Versioned SDK libraries, templates, schemas and documentation for Luau and Odin. The manifest records the compressed bundle's SHA-256 and size.";
await writeFile(
  resolve(output, "release-notes.md"),
  `${notes}\n\n` +
    "Build, check, run, watch, pack and import still require the source CLI. Managed compilers and prebuilt players are not included in this preview.\n\n" +
    "[Getting started](https://bytor.io/docs/docs/getting-started.html) explains supported commands and the source fallback.\n\n" +
    `Source: tag \`${release.tag}\`. Windows and Apple Silicon run the full validation suite; Intel Mac runs the standalone CLI suite.\n`,
);
console.log(`Packaged ${release.tag}`);

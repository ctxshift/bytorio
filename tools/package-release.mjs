import { copyFile, mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { releaseConfig } from "./release-config.mjs";
import { repo, script } from "./toolchain.mjs";
import { requireCliHost } from "./host-platform.mjs";

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
const notes =
  release.kind === "byt"
    ? "Standalone scaffolding preview for Windows x64 and macOS Apple Silicon/Intel. Download byt.exe on Windows, byt-macos-arm64 on Apple Silicon, or byt-macos-x64 on Intel. Each binary has a platform-specific SHA-256 manifest. On macOS, rename the download to byt and run chmod +x byt. Supports new and sdk install without Node, Bun or mise. Mac binaries are ad hoc signed; these previews are not notarized or signed with a distribution identity."
    : "Versioned SDK libraries, templates, schemas and documentation for Luau and Odin. The manifest records the compressed bundle's SHA-256 and size.";
await writeFile(
  resolve(output, "release-notes.md"),
  `${notes}\n\n` +
    "Build, check, run, watch, pack and import still require the source CLI. Managed compilers and prebuilt players are not included in this preview.\n\n" +
    "[Getting started](https://bytor.io/docs/docs/getting-started.html) explains supported commands and the source fallback.\n\n" +
    `Source: tag \`${release.tag}\`. Windows and Apple Silicon run the full validation suite; Intel Mac runs the standalone CLI suite.\n`,
);
console.log(`Packaged ${release.tag}`);

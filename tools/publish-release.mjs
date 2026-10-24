import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { releaseConfig, verifyReleaseAsset } from "./release-config.mjs";
import { repo, run } from "./toolchain.mjs";

const release = releaseConfig(process.env.BYTORIO_RELEASE_TAG);
const directory = resolve(repo, "build/releases", release.tag);
const manifestName = release.kind === "byt" ? "release.json" : "sdk-release.json";
const assetName = release.kind === "byt" ? "byt.exe" : `bytorio-sdk-${release.version}.json.gz`;
const manifest = JSON.parse(await readFile(resolve(directory, manifestName), "utf8"));
const bytes = await readFile(resolve(directory, assetName));
verifyReleaseAsset(release, manifest, bytes);
if (process.argv.includes("--check")) {
  console.log(`Verified release assets for ${release.tag}`);
} else {
  // gh creates a draft, uploads every asset, then publishes. An existing release
  // fails rather than replacing files clients may already have pinned.
  const args = [
    "release",
    "create",
    release.tag,
    "--verify-tag",
    "--title",
    `Bytorio ${release.kind === "byt" ? "CLI (Windows x64)" : "SDK"} ${release.version}`,
    "--notes-file",
    resolve(directory, "release-notes.md"),
    resolve(directory, manifestName),
    resolve(directory, assetName),
  ];
  if (release.prerelease) {
    args.push("--prerelease");
  }
  console.log(run("gh", args, { timeout: 600000 }));
}

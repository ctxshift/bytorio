import { checkVersion } from "./cli/sdk-bundle.ts";
import { createHash } from "node:crypto";

export function releaseConfig(tag) {
  const match = /^(byt|sdk)-v(.+)$/.exec(tag ?? "");
  if (!match) {
    throw new Error("Expected a byt-v<version> or sdk-v<version> release tag");
  }
  const version = checkVersion(match[2]);
  const kind = match[1];
  return { tag, kind, version, prerelease: version.includes("-") };
}

export function cliVersion(tag) {
  if (!tag) {
    return "0.1.0-preview.1";
  }
  const release = releaseConfig(tag);
  return release.kind === "byt" ? release.version : "0.1.0-preview.1";
}

export function verifyReleaseAsset(release, manifest, bytes) {
  const filename = release.kind === "byt" ? "byt.exe" : `bytorio-sdk-${release.version}.json.gz`;
  if (
    manifest.version !== release.version ||
    manifest.bytes !== bytes.length ||
    manifest.sha256 !== createHash("sha256").update(bytes).digest("hex") ||
    (release.kind === "byt" ? manifest.executable !== filename : manifest.asset !== filename)
  ) {
    throw new Error("Release version, size, filename or checksum does not match its asset");
  }
}

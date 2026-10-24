import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { test } from "node:test";
import { cliVersion, releaseConfig, verifyReleaseAsset } from "./release-config.mjs";

test("release tags select independent versions and prerelease status", () => {
  assert.deepEqual(releaseConfig("byt-v1.2.3-rc.2"), {
    tag: "byt-v1.2.3-rc.2",
    kind: "byt",
    version: "1.2.3-rc.2",
    prerelease: true,
  });
  assert.equal(releaseConfig("sdk-v2.0.0").prerelease, false);
  assert.equal(cliVersion("byt-v1.2.3-rc.2"), "1.2.3-rc.2");
  assert.equal(cliVersion("sdk-v2.0.0"), cliVersion());
  for (const tag of [
    undefined,
    "main",
    "byt-v../escape",
    "sdk-v1",
    "byt-v1.0.0\n",
    "other-v1.0.0",
  ]) {
    assert.throws(() => releaseConfig(tag));
  }
});

test("publication refuses mismatched versions, filenames, size and corrupted bytes", () => {
  const bytes = Buffer.from("release fixture");
  for (const kind of ["byt", "sdk"]) {
    const release = releaseConfig(`${kind}-v1.2.3`);
    const filenameKey = kind === "byt" ? "executable" : "asset";
    const manifest = {
      version: "1.2.3",
      bytes: bytes.length,
      sha256: createHash("sha256").update(bytes).digest("hex"),
      [filenameKey]: kind === "byt" ? "byt.exe" : "bytorio-sdk-1.2.3.json.gz",
    };
    verifyReleaseAsset(release, manifest, bytes);
    for (const change of [
      { version: "1.2.4" },
      { bytes: bytes.length + 1 },
      { sha256: "0".repeat(64) },
      { [filenameKey]: "wrong-file" },
    ]) {
      assert.throws(() => verifyReleaseAsset(release, { ...manifest, ...change }, bytes));
    }
    assert.throws(() => verifyReleaseAsset(release, manifest, Buffer.from("changed fixture")));
  }
});

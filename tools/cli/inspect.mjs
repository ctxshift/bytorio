import { createHash } from "node:crypto";
import { lstat, readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { readGameProject } from "./project-config.mjs";
import { publishedReleases, resolveSdkRelease } from "./sdk-registry.mjs";
import { orderedSdkVersions } from "./sdk-manifest.mjs";
import { resolveComponent } from "./component-cache.mjs";

export function comparablePlayerBytes(path, bytes) {
  if (!["player.html", "debug.html"].includes(path)) {
    return bytes;
  }
  let html = bytes.toString("utf8").replace(/<title>.*?<\/title>/, "<title></title>");
  if (path === "debug.html") {
    html = html.replace(
      /<script>globalThis\.playerCartridge="\.\/game\.png\?revision=[a-f0-9]+"<\/script>\n/,
      "",
    );
  }
  return Buffer.from(html);
}

export async function latestReleases(options = {}) {
  const catalogue = await publishedReleases(options);
  const result = { policy: options.allowPrerelease === false ? "stable" : "including-previews" };
  for (const [kind, prefix] of [
    ["cli", "byt-v"],
    ["sdk", "sdk-v"],
  ]) {
    const eligible = catalogue.filter(
      (release) =>
        typeof release.tag_name === "string" &&
        release.tag_name.startsWith(prefix) &&
        (options.allowPrerelease !== false || !release.prerelease),
    );
    const [version] = orderedSdkVersions(
      eligible.map((release) => release.tag_name.slice(prefix.length)),
      {
        allowPrerelease: options.allowPrerelease !== false,
      },
    );
    const release = eligible.find((entry) => entry.tag_name === prefix + version);
    if (!release) {
      throw new Error(`No published ${kind} release matches the selected policy`);
    }
    result[kind] = { version, tag: release.tag_name, publishedAt: release.published_at ?? null };
  }
  return result;
}

export async function comparePlayerFiles(directory, files) {
  const modified = [];
  const missing = [];
  for (const file of files) {
    const path = resolve(directory, file.path);
    try {
      if (
        !(await lstat(path)).isFile() ||
        createHash("sha256")
          .update(comparablePlayerBytes(file.path, await readFile(path)))
          .digest("hex") !== file.sha256
      ) {
        modified.push(file.path);
      }
    } catch (error) {
      if (error.code !== "ENOENT") {
        throw error;
      }
      missing.push(file.path);
    }
  }
  return {
    status: modified.length || missing.length ? "differs-from-pinned-sdk" : "matches-pinned-sdk",
    modified,
    missing,
  };
}

export async function inspectPreview(directory, options = {}) {
  const project = await readGameProject(directory);
  const release = await resolveSdkRelease(project.pin.version, {
    ...options,
    expectedSha256: project.pin.sha256,
  });
  const root = (
    options.releaseRoot ?? "https://github.com/ctxshift/bytorio/releases/download"
  ).replace(/\/$/, "");
  const ids = [...new Set(Object.values(release.manifest.web).map((ref) => ref.component))];
  if (!ids.length) {
    throw new Error("Pinned SDK has no web player inventory");
  }
  const files = [];
  for (const id of ids) {
    const descriptor = release.manifest.components[id];
    const component = await resolveComponent(
      { id, descriptor, url: `${root}/sdk-v${project.pin.version}/${descriptor.asset}` },
      options,
    );
    for (const file of component.inventory.files) {
      if (["player.html", "debug.html"].includes(file.path)) {
        const bytes = await readFile(resolve(component.directory, file.path));
        files.push({
          ...file,
          sha256: createHash("sha256")
            .update(comparablePlayerBytes(file.path, bytes))
            .digest("hex"),
        });
      } else {
        files.push(file);
      }
    }
  }
  return {
    sdk: project.pin.version,
    metadataSha256: project.pin.sha256,
    export: options.export ?? "build/web",
    ...(await comparePlayerFiles(resolve(project.directory, options.export ?? "build/web"), files)),
    note: "Compares SDK web component files, allowing generated page titles and the debug cartridge revision. Game content, player configuration and extra host files are outside this comparison. A difference can be an intentional local override or a stale export; it is not an automatic upgrade.",
  };
}

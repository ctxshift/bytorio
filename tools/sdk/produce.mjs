import { copyFile, cp, mkdir, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { basename, resolve } from "node:path";
import { branding } from "../branding.mjs";
import { requireNativeHost } from "../host-platform.mjs";
import { exportExecutor, exportPlayer } from "../player-export.mjs";
import { repo, run, tool } from "../toolchain.mjs";
import { packComponent } from "./component.mjs";
import { parseSdkManifest, sdkReleaseVersion } from "../cli/sdk-manifest.mjs";

// Produce a host-qualified candidate. Publishing and cross-host assembly are separate steps.
export async function produceLuauWebSdk({ version, cliVersionRange, output }) {
  sdkReleaseVersion(version);
  const host = requireNativeHost();
  if (!output) {
    throw new Error("SDK candidate output directory is required");
  }
  const ref = (component, path) => ({ component, path });
  const contract = JSON.parse(await readFile(resolve(repo, "sdk/contract.json"), "utf8"));
  const analyzer = basename(tool("luau-analyze"));
  const toolsId = `luau-${host.id}`;
  const manifest = {
    schema: 2,
    version,
    cliProtocol: 2,
    cliVersionRange,
    profiles: contract.profiles,
    limits: contract.limits,
    defaults: {
      profile: contract.profile,
      display: contract.defaultDisplayMode,
      assets: ref("core", "sdk/templates/assets.json"),
    },
    starters: {
      luau: {
        entry: "src/main.luau",
        source: (await readFile(resolve(repo, "sdk/templates/main.luau"), "utf8")).replaceAll(
          "__STARTER_MESSAGE__",
          branding.starterMessage,
        ),
      },
    },
    components: {},
    authoring: ref("core", "authoring.mjs"),
    contract: ref("core", "sdk/contract.json"),
    check: {
      runtime: ref("checks", "runtime.wasm"),
      workers: { luau: ref("checks", "check-worker.mjs") },
      luauExecutor: ref("executor", "luau-executor.wasm"),
    },
    // The candidate still uses the legacy shell until the public runtime extraction lands.
    web: {
      runtime: ref("web", "player.js"),
      player: ref("web", "player.js"),
      page: ref("web", "player.html"),
    },
    languages: {
      luau: {
        libraries: ref("core", "sdk/luau"),
        hosts: { [host.id]: { analyzer: ref(toolsId, analyzer) } },
      },
    },
    native: {},
  };
  // Validate caller metadata before reserving the output or invoking a build.
  const placeholder = {
    asset: "candidate.tar.gz",
    format: "tar.gz",
    bytes: 1,
    expandedBytes: 1,
    files: 1,
    sha256: "0".repeat(64),
    inventorySha256: "0".repeat(64),
  };
  const ids = ["core", toolsId, "checks", "executor", "web"];
  manifest.components = Object.fromEntries(ids.map((id) => [id, placeholder]));
  parseSdkManifest(Buffer.from(JSON.stringify(manifest)), version);

  output = resolve(output);
  await mkdir(output); // Exclusive reservation: never replace an earlier candidate.
  const payloads = resolve(output, ".payloads");
  try {
    for (const id of ids) {
      await mkdir(resolve(payloads, id), { recursive: true });
    }
    const core = resolve(payloads, "core");
    await cp(resolve(repo, "sdk"), resolve(core, "sdk"), { recursive: true });
    run(tool("bun"), [
      "build",
      "--target=bun",
      "tools/sdk/authoring.mjs",
      "--outfile",
      resolve(core, "authoring.mjs"),
    ]);
    const checks = resolve(payloads, "checks");
    await copyFile(
      resolve(repo, "build/odin-player/web/runtime.wasm"),
      resolve(checks, "runtime.wasm"),
    );
    await mkdir(resolve(checks, "licenses"));
    await copyFile(
      resolve(repo, "build/odin-player/web/licenses/odin.txt"),
      resolve(checks, "licenses/odin.txt"),
    );
    run(tool("bun"), [
      "build",
      "--target=bun",
      "tools/sdk/smoke-worker.mjs",
      "--outfile",
      resolve(checks, "check-worker.mjs"),
    ]);
    const executor = await exportExecutor({ target: resolve(payloads, "executor") });
    await copyFile(tool("luau-analyze"), resolve(payloads, toolsId, analyzer));
    await mkdir(resolve(payloads, toolsId, "licenses"));
    await copyFile(
      resolve(repo, "build/luau-executor/_deps/luau-src/LICENSE.txt"),
      resolve(payloads, toolsId, "licenses/luau.txt"),
    );
    await exportPlayer({
      platform: "web",
      source: resolve(repo, "build/odin-player/web"),
      target: resolve(payloads, "web"),
    });
    const webNotices = (await readdir(resolve(payloads, "web/licenses"))).map(
      (name) => `licenses/${name}`,
    );
    const notices = {
      core: ["sdk/NOTICE"],
      [toolsId]: ["licenses/luau.txt"],
      checks: ["licenses/odin.txt"],
      executor: executor.notices,
      web: webNotices,
    };
    const archives = new Map();
    for (const id of ids) {
      const asset = `bytorio-sdk-${version}-${id}.tar.gz`;
      const archive = resolve(output, asset);
      manifest.components[id] = {
        asset,
        ...(await packComponent({
          root: resolve(payloads, id),
          archive,
          notices: notices[id],
          executables: id === toolsId ? [analyzer] : [],
        })),
      };
      archives.set(asset, archive);
    }
    const metadata = Buffer.from(JSON.stringify(manifest, null, 2) + "\n");
    parseSdkManifest(metadata, version);
    await rm(payloads, { recursive: true });
    // Publish the manifest last; an interrupted build is not a usable candidate.
    await writeFile(resolve(output, "sdk-release.json"), metadata, { flag: "wx" });
    return { manifest, metadata, archives, output };
  } catch (error) {
    await rm(output, { recursive: true, force: true });
    throw error;
  }
}

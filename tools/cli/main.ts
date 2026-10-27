import { createScaffolder } from "../sdk/scaffold.mjs";
import { branding, version } from "../../build/cli/assets";
import { writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { hostPlatform } from "../host-platform.mjs";
import { resolveDistribution } from "./distribution.mjs";
import { assertNewProject, createGameProject, selectProjectSdk } from "./project-config.mjs";

type Language = "luau" | "odin";

const help = `${branding.name} CLI ${version}

Usage: byt new <directory> [--language luau|odin] [--sdk <version>] [--offline]
       byt sdk install <version> [--offline]
       byt --help
       byt --version

New games use bytorio.toml and bytorio.lock.toml, with Luau by default.
The newest compatible installed SDK is preferred; previews are eligible.
Players and tools are downloaded only when needed.
Other authoring commands are being connected in this development build.`;

function sdkOptions(offline: boolean) {
  return {
    offline,
    cliVersion: version,
    host: hostPlatform().id,
    cache: process.env.BYTORIO_CACHE_DIR,
    releaseRoot: process.env.BYTORIO_SDK_RELEASE_ROOT,
    catalogueRoot: process.env.BYTORIO_SDK_CATALOGUE_URL,
  };
}

async function main(args: string[]): Promise<void> {
  if (args.length === 0 || (args.length === 1 && ["--help", "help"].includes(args[0]))) {
    console.log(help);
    return;
  }
  if (args.length === 1 && args[0] === "--version") {
    console.log(version);
    return;
  }
  if (["check", "build", "run", "watch", "pack", "import"].includes(args[0])) {
    throw new Error(
      `${args[0]} is not available in this standalone preview. Use the source CLI until managed toolchains and player bundles are implemented.`,
    );
  }
  if (args[0] === "sdk") {
    if (
      args[1] !== "install" ||
      !args[2] ||
      args.length > 4 ||
      (args.length === 4 && args[3] !== "--offline")
    ) {
      throw new Error("Expected: byt sdk install <version> [--offline]");
    }
    await resolveDistribution(args[2], sdkOptions(args[3] === "--offline"));
    console.log(`SDK ${args[2]} is cached and verified`);
    return;
  }
  if (args[0] !== "new" || !args[1] || args[1].startsWith("--")) {
    throw new Error(help);
  }
  let language: Language = "luau";
  let sdk: string | undefined;
  let offline = false;
  const seen = new Set<string>();
  for (let index = 2; index < args.length; index++) {
    const flag = args[index];
    if (seen.has(flag)) throw new Error(`Duplicate option: ${flag}`);
    seen.add(flag);
    if (flag === "--offline") {
      offline = true;
    } else if (flag === "--language" && ["luau", "odin"].includes(args[index + 1])) {
      language = args[++index] as Language;
    } else if (flag === "--sdk" && args[index + 1]) {
      sdk = args[++index];
    } else {
      throw new Error(`Invalid option: ${flag}`);
    }
  }
  await assertNewProject(args[1]);
  const options = sdkOptions(offline);
  const distribution = sdk ? await resolveDistribution(sdk, options) : undefined;
  if (distribution?.legacy) {
    const legacy = distribution.legacy;
    const { createProject } = await createScaffolder({
      branding: { ...branding, ...legacy.bundle.branding },
      readAsset: async (path: string) => {
        const contents = legacy.bundle.assets[path];
        if (contents === undefined) {
          throw new Error(`Missing legacy SDK asset: ${path}`);
        }
        return contents;
      },
    });
    const project = await createProject(args[1], language);
    await writeFile(
      resolve(project, "byt.lock.json"),
      JSON.stringify(
        {
          schema: 1,
          sdk: { version: legacy.manifest.version, sha256: legacy.manifest.sha256 },
        },
        null,
        2,
      ) + "\n",
      { flag: "wx" },
    );
    console.log("Created a legacy scaffold. Full authoring requires a protocol-2 SDK project.");
    return;
  }
  const release = await selectProjectSdk(language, sdk, options);
  const project = await createGameProject(args[1], language, release);
  console.log(`Created ${language} game: ${project}`);
  console.log(`Pinned SDK ${release.manifest.version}. Run byt run inside the project to play.`);
}

try {
  await main(process.argv.slice(2));
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}

import { createScaffolder } from "../sdk/scaffold.mjs";
import { assets, branding, version } from "../../build/cli/assets";
import { writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { resolveSdk } from "./sdk-bundle";

type Language = "luau" | "odin";

const help = `${branding.name} standalone CLI preview ${version}

Usage: byt new <directory> [--language luau|odin] [--sdk <version>] [--offline]
       byt sdk install <version> [--offline]
       byt --help
       byt --version

This preview creates projects offline using its embedded SDK.
check, build, run, watch, pack and import still require the source CLI.
Prebuilt player bundles and managed compiler installation are not available yet.`;

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
    await resolveSdk(args[2], { offline: args[3] === "--offline" });
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
  const release = sdk ? await resolveSdk(sdk, { offline }) : undefined;
  const selectedAssets = release?.bundle.assets ?? assets;
  const { createProject } = await createScaffolder({
    branding: release?.bundle.branding ?? branding,
    readAsset: async (path: string) => {
      const contents = selectedAssets[path];
      if (contents === undefined) {
        throw new Error(`Missing embedded SDK asset: ${path}`);
      }
      return contents;
    },
  });
  const project = await createProject(args[1], language);
  if (release) {
    await writeFile(
      resolve(project, "byt.lock.json"),
      JSON.stringify(
        {
          schema: 1,
          sdk: { version: release.manifest.version, sha256: release.manifest.sha256 },
        },
        null,
        2,
      ) + "\n",
      { flag: "wx" },
    );
  }
}

try {
  await main(process.argv.slice(2));
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}

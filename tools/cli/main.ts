import { createScaffolder } from "../sdk/scaffold.mjs";
import { assets, branding, version } from "../../build/cli/assets";

type Language = "luau" | "odin";

const help = `${branding.name} standalone CLI preview ${version}

Usage: byt new <directory> [--language luau|odin]
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
  if (args[0] !== "new" || !args[1] || args[1].startsWith("--")) {
    throw new Error(help);
  }
  let language: Language = "luau";
  if (args.length !== 2) {
    if (
      args.length !== 4 ||
      args[2] !== "--language" ||
      (args[3] !== "luau" && args[3] !== "odin")
    ) {
      throw new Error("Expected: byt new <directory> [--language luau|odin]");
    }
    language = args[3];
  }
  const { createProject } = await createScaffolder({
    branding,
    readAsset: async (path: string) => {
      const contents = assets[path];
      if (contents === undefined) {
        throw new Error(`Missing embedded SDK asset: ${path}`);
      }
      return contents;
    },
  });
  await createProject(args[1], language);
}

try {
  await main(process.argv.slice(2));
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}

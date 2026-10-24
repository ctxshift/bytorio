import { mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { createHash } from "node:crypto";
import { branding } from "./branding.mjs";
import { repo, run, tool } from "./toolchain.mjs";
import { cliVersion } from "./release-config.mjs";

if (process.platform !== "win32" || process.arch !== "x64") {
  throw new Error("Standalone CLI preview is currently qualified only for Windows x64");
}

const output = resolve(repo, "build/cli");
await mkdir(output, { recursive: true });
const paths = ["sdk/contract.json"];
for (const directory of ["sdk/templates", "sdk/luau"]) {
  for (const entry of await readdir(resolve(repo, directory), { withFileTypes: true })) {
    if (entry.isFile() && /\.(json|luau|odin)$/.test(entry.name)) {
      paths.push(`${directory}/${entry.name}`);
    }
  }
}
const assets = Object.fromEntries(
  await Promise.all(
    paths.sort().map(async (path) => [path, await readFile(resolve(repo, path), "utf8")]),
  ),
);
const version = cliVersion(process.env.BYTORIO_RELEASE_TAG);
await writeFile(
  resolve(output, "assets.ts"),
  `export const assets: Record<string, string> = ${JSON.stringify(assets)};\n` +
    `export const branding = ${JSON.stringify(branding)};\n` +
    `export const version = ${JSON.stringify(version)};\n`,
);
run(process.execPath, [
  resolve(repo, "node_modules/typescript/bin/tsc"),
  "-p",
  "tools/cli/tsconfig.json",
]);
const executable = resolve(output, "byt.exe");
run(tool("bun"), [
  "build",
  "--compile",
  "--no-compile-autoload-dotenv",
  "--no-compile-autoload-bunfig",
  "--no-compile-autoload-tsconfig",
  "--no-compile-autoload-package-json",
  "tools/cli/main.ts",
  "--outfile",
  executable,
]);
const bytes = await readFile(executable);
await writeFile(
  resolve(output, "release.json"),
  JSON.stringify(
    {
      version,
      platform: "windows-x64",
      status: "scaffolding-preview",
      executable: "byt.exe",
      bytes: bytes.length,
      sha256: createHash("sha256").update(bytes).digest("hex"),
      sdkAssets: paths.sort(),
    },
    null,
    2,
  ) + "\n",
);
console.log(`Built standalone CLI preview: build/cli/byt.exe (${bytes.length} bytes)`);

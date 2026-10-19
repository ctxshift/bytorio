import { dirname, resolve } from "node:path";
import { sourceFiles } from "./code-tools.mjs";
import { repo, run, tool, dependencyRoot } from "./toolchain.mjs";

const language = process.argv[2];
if (!["odin", "luau"].includes(language)) {
  throw new Error("Specify odin or luau");
}
const files = sourceFiles(`.${language}`);
if (language === "luau") {
  const output = run(tool("luau-analyze"), ["--formatter=gnu", ...files]);
  if (output) {
    console.log(output);
  }
  console.log(`Luau type checking and lint passed: ${files.length} files.`);
} else {
  const packages = [...new Set(files.map(dirname))].sort();
  const failures = [];
  for (const pkg of packages) {
    const native =
      pkg.includes("/native") ||
      pkg.includes("/guest") ||
      pkg.endsWith("/player") ||
      pkg === "experiments/odin" ||
      pkg === "tests/graphics" ||
      pkg === "tests/resources";
    const args = [
      "check",
      pkg,
      "-no-entry-point",
      "-vet",
      `-collection:sdk=${resolve(repo, "sdk/odin")}`,
      `-collection:deps=${dependencyRoot()}`,
    ];
    if (!native) {
      args.push("-target:freestanding_wasm32");
    }
    try {
      run(tool("odin"), args);
    } catch (error) {
      failures.push(`${pkg}:\n${error.message}`);
    }
  }
  if (failures.length) {
    throw new Error(failures.join("\n"));
  }
  console.log(`Odin check -vet passed: ${packages.length} packages, ${files.length} files.`);
}

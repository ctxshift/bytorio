import { readdirSync } from "node:fs";
import { dirname, resolve, extname } from "node:path";
import { languageFiles } from "./code-tools.mjs";
import { repo, run, tool, dependencyRoot, emscriptenRoot, task } from "./toolchain.mjs";

const language = process.argv[2];
if (!["odin", "luau", "cpp"].includes(language)) {
  throw new Error("Specify odin, luau or cpp");
}
const files = languageFiles(language);
if (language === "cpp") {
  task("deps:luau:configure");
  const emscripten = emscriptenRoot();
  const resourceRoot = resolve(emscripten, "../lib/clang");
  const versions = readdirSync(resourceRoot).filter((name) => /^\d+$/.test(name));
  if (versions.length !== 1) {
    throw new Error("Expected one Clang resource directory in the pinned Emscripten SDK");
  }
  const sources = files.filter((file) => [".cpp", ".cc", ".cxx"].includes(extname(file)));
  if (!sources.length) {
    throw new Error("No C++ translation units found");
  }
  // Keep CMake's real includes/defines; use the SDK's Wasm target and system headers
  // because the standalone clang-tidy executable otherwise assumes the host target.
  run(
    tool("clang-tidy"),
    [
      ...sources,
      "-p=build/luau-executor",
      "--quiet",
      "--extra-arg=--target=wasm32-unknown-emscripten",
      `--extra-arg=--sysroot=${resolve(emscripten, "cache/sysroot")}`,
      `--extra-arg=-resource-dir=${resolve(resourceRoot, versions[0])}`,
    ],
    { stdio: "inherit" },
  );
  console.log(
    `C++ clang-tidy passed: ${sources.length} translation units and their project headers.`,
  );
} else if (language === "luau") {
  const output = run(tool("luau-analyze"), ["--solver=new", "--formatter=gnu", ...files]);
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
      pkg === "tests/3d" ||
      pkg === "examples/kart3d/tests" ||
      pkg === "tests/resources" ||
      pkg === "tests/timing" ||
      pkg === "tests/sdk/input" ||
      pkg === "tests/audio";
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

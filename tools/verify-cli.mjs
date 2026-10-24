import assert from "node:assert/strict";
import { copyFile, mkdir, mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve, sep } from "node:path";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { createProject } from "./sdk/project.mjs";
import { repo } from "./toolchain.mjs";

const temporaryRoot = resolve(tmpdir());
const sandbox = await mkdtemp(join(temporaryRoot, "bytorio-cli-"));
assert.ok(sandbox.startsWith(temporaryRoot + sep), "Unexpected verification directory");
const reportDirectory = resolve(repo, "build/cli-verification");
await mkdir(reportDirectory, { recursive: true });
const executable = resolve(sandbox, "byt.exe");
const environment = Object.fromEntries(
  Object.entries(process.env).filter(([name]) => !/^(path|mise.*|node.*|bun.*)$/i.test(name)),
);
environment.PATH = "";

function invoke(args, success = true) {
  const result = spawnSync(executable, args, {
    cwd: sandbox,
    env: environment,
    encoding: "utf8",
    timeout: 30000,
    windowsHide: true,
  });
  assert.ifError(result.error);
  if (success) {
    assert.equal(result.status, 0, result.stderr);
  } else {
    assert.notEqual(result.status, 0, "Invalid command unexpectedly succeeded");
    assert.equal(result.signal, null, "Command crashed instead of rejecting input");
  }
  return result;
}

async function inventory(root, prefix = "") {
  const files = {};
  for (const entry of await readdir(resolve(root, prefix), { withFileTypes: true })) {
    const name = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) {
      Object.assign(files, await inventory(root, name));
    } else {
      const bytes = await readFile(resolve(root, name));
      files[name] = createHash("sha256").update(bytes).digest("hex");
    }
  }
  return files;
}

try {
  await copyFile(resolve(repo, "build/cli/byt.exe"), executable);
  // Ambient project configuration must not redirect a compiled CLI's runtime.
  await writeFile(resolve(sandbox, ".env"), "NODE_OPTIONS=--invalid-byt-option\n");
  await writeFile(resolve(sandbox, "bunfig.toml"), 'preload = ["./missing.js"]\n');
  assert.match(invoke(["--help"]).stdout, /standalone CLI preview/);
  assert.match(invoke(["--version"]).stdout, /^0\.1\.0-preview\.1\s*$/);
  const projects = [];
  for (const language of ["luau", "odin"]) {
    const name = `${language} game with spaces`;
    const args = language === "luau" ? ["new", name] : ["new", name, "--language", language];
    invoke(args);
    const standalone = resolve(sandbox, name);
    const source = resolve(sandbox, `${language} source reference`);
    await createProject(source, language);
    const files = await inventory(standalone);
    assert.deepEqual(
      files,
      await inventory(source),
      `${language} scaffold differs from source CLI`,
    );
    const manifest = JSON.parse(await readFile(resolve(standalone, "console.json"), "utf8"));
    assert.equal(manifest.language, language);
    assert.equal(manifest.profile, "resource-av-1");
    assert.ok(files[`src/main.${language}`]);
    assert.ok(files[".bytorio/bytorio.luau"]);
    assert.match(invoke(args, false).stderr, /exist/i);
    assert.deepEqual(await inventory(standalone), files, "Existing project was modified");
    projects.push({ language, files: Object.keys(files).length });
  }
  for (const args of [
    ["new", "invalid", "--language", "python"],
    ["new", "invalid", "--language"],
    ["new", "invalid", "--surprise"],
    ["new", "invalid", "--language", "odin", "extra"],
    ["new"],
    ["unknown"],
    ["--help", "extra"],
  ]) {
    invoke(args, false);
  }
  assert.equal(existsSync(resolve(sandbox, "invalid")), false);
  for (const action of ["check", "build", "run", "watch", "pack", "import"]) {
    assert.match(invoke([action, "luau game with spaces"], false).stderr, /not available/);
  }
  await writeFile(
    resolve(reportDirectory, "report.json"),
    JSON.stringify({ status: "passed", isolatedCwd: true, emptyPath: true, projects }, null, 2) +
      "\n",
  );
  console.log(
    "Standalone CLI passed: offline scaffolds match both SDKs, empty PATH, existing files preserved, unsupported commands rejected.",
  );
} finally {
  await rm(sandbox, { recursive: true, force: true });
}

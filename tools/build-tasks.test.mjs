import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  appendFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, matchesGlob, relative, resolve } from "node:path";
import { test } from "node:test";
import { repo } from "./toolchain.mjs";

const mise = process.env.MISE_BIN || "mise";

function execute(args, cwd = repo, env = process.env) {
  const result = spawnSync(mise, args, { cwd, env, encoding: "utf8", timeout: 30000 });
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stderr + result.stdout);
  return result.stdout;
}

const tasks = JSON.parse(execute(["tasks", "ls", "--json"])).filter(
  ({ name }) => name === "build:odin" || name.startsWith("deps:player:"),
);
const byName = new Map(tasks.map((task) => [task.name, task]));
const forward = (path) => path.replaceAll("\\", "/");

function covered(file, sources) {
  return sources.some((pattern) => matchesGlob(forward(file), pattern));
}

// This checks the declared input contract against the actual import tree. It is
// deliberately a test, not a second production dependency resolver or cache.
function packageInputs(entry, seen = new Set()) {
  if (seen.has(entry)) {
    return [];
  }
  seen.add(entry);
  const files = [];
  for (const name of readdirSync(resolve(repo, entry))) {
    if (!name.endsWith(".odin")) {
      continue;
    }
    const file = forward(join(entry, name));
    files.push(file);
    const source = readFileSync(resolve(repo, file), "utf8");
    for (const [, dependency] of source.matchAll(/^\s*import\s+(?:[^\s"]+\s+)?"([^"\n]+)"/gm)) {
      if (dependency.startsWith(".")) {
        files.push(...packageInputs(forward(join(entry, dependency)), seen));
      } else if (dependency.startsWith("sdk:")) {
        files.push(...packageInputs(`sdk/odin/${dependency.slice(4)}`, seen));
      }
    }
    for (const [, dependency] of source.matchAll(/#load\("([^"\n]+)"\)/g)) {
      files.push(forward(join(entry, dependency)));
    }
  }
  return files;
}

test("compiled tasks cover local Odin imports and embedded shader inputs", () => {
  const entries = {
    "deps:player:web-cpu": "runtime/odin/web",
    "deps:player:web-gpu": "runtime/odin/web",
    "deps:player:web-audio": "runtime/odin/audio_web",
    "deps:player:native-binary": "runtime/odin/native",
    "deps:player:hello": "examples/hello-odin",
    "deps:player:fixtures": "tests/odin/fixtures",
  };
  for (const [name, entry] of Object.entries(entries)) {
    const task = byName.get(name);
    assert.ok(task, name);
    for (const file of packageInputs(entry)) {
      assert.ok(covered(file, task.sources), `${name} omits ${file}`);
    }
    assert.ok(covered(".mise/toolchain.toml", task.sources), `${name} omits toolchain pins`);
  }
});

function put(root, file, text) {
  const path = resolve(root, file);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, text);
}

function fixture() {
  const root = mkdtempSync(join(tmpdir(), "player-build-cache-"));
  const env = {
    ...process.env,
    MISE_TRUSTED_CONFIG_PATHS: root,
    MISE_TASK_RUN_AUTO_INSTALL: "false",
  };
  const definitions = new Map();
  const outputs = {};
  for (const task of tasks) {
    const file = forward(relative(repo, task.source));
    const header =
      file === "mise.toml" ? `tasks.${JSON.stringify(task.name)}` : JSON.stringify(task.name);
    let text = `[${header}]\n`;
    for (const key of ["sources", "outputs", "depends"]) {
      if (task[key]?.length) {
        text += `${key} = ${JSON.stringify(task[key])}\n`;
      }
    }
    if (task.outputs.length) {
      outputs[task.name] = task.outputs;
      text += `run = ${JSON.stringify(`node cache-fixture.mjs ${task.name}`)}\n`;
    }
    definitions.set(file, (definitions.get(file) || "") + text + "\n");
  }
  const config = '[task_config]\nincludes = [".mise/tasks/*.toml"]\n\n';
  definitions.set("mise.toml", config + (definitions.get("mise.toml") || ""));
  for (const [file, content] of definitions) {
    put(root, file, content);
  }
  put(root, "outputs.json", JSON.stringify(outputs));
  put(root, "events.jsonl", "");
  put(
    root,
    "cache-fixture.mjs",
    `import { mkdirSync, readFileSync, appendFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
const name = process.argv[2];
for (const file of JSON.parse(readFileSync("outputs.json"))[name]) {
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, name + "\\n");
}
appendFileSync("events.jsonl", JSON.stringify(name) + "\\n");
`,
  );
  // Only inputs needed for the invalidation scenarios: no compilers or real
  // build artifacts are used by this scheduler regression test.
  for (const file of [
    ".mise/toolchain.toml",
    "runtime/odin/web/player.js",
    "runtime/odin/web/constants.js",
    "runtime/odin/web/main.odin",
    "runtime/odin/resources/resources.odin",
    "runtime/odin/native/main_windows.odin",
    "runtime/odin/gpu/mesh.frag",
    "runtime/odin/abi/abi.odin",
    "tests/odin/fixtures/main.odin",
    "examples/hello-odin/main.odin",
    "tests/3d/renderer_test.odin",
    "tests/resources/player/main_windows.odin",
    "tests/graphics/player/main_windows.odin",
    "tests/audio/player/main_windows.odin",
  ]) {
    put(root, file, "fixture\n");
  }
  function run(...names) {
    writeFileSync(resolve(root, "events.jsonl"), "");
    for (const name of names) {
      execute(["run", "--jobs", "1", name], root, env);
    }
    return readFileSync(resolve(root, "events.jsonl"), "utf8")
      .trim()
      .split("\n")
      .filter(Boolean)
      .map(JSON.parse)
      .sort();
  }
  return { root, run, outputs };
}

test("mise rebuilds only the artifacts affected by edits and missing outputs", async () => {
  const { root, run, outputs } = fixture();
  const targets = ["build:odin"];
  const all = Object.keys(outputs).sort();
  assert.deepEqual(run(...targets), all);
  assert.deepEqual(run(...targets), [], "unchanged inputs reuse every artifact");

  async function edit(file, expected) {
    // Separate modification times on filesystems whose clock has millisecond precision.
    await new Promise((done) => setTimeout(done, 20));
    appendFileSync(resolve(root, file), "\n# changed\n");
    assert.deepEqual(run(...targets), expected.sort(), file);
  }
  await edit("runtime/odin/web/player.js", ["deps:player:web-support"]);
  await edit("tests/3d/renderer_test.odin", []);
  await edit("mise.toml", []);
  await edit("runtime/odin/gpu/mesh.frag", [
    "deps:player:native-binary",
    "deps:player:web-support",
  ]);
  await edit("tests/odin/fixtures/main.odin", ["deps:player:fixtures"]);
  await edit("examples/hello-odin/main.odin", ["deps:player:hello"]);
  await edit("runtime/odin/web/main.odin", ["deps:player:web-cpu", "deps:player:web-gpu"]);
  await edit("runtime/odin/native/main_windows.odin", ["deps:player:native-binary"]);
  put(root, "runtime/odin/web/new_module.odin", "package web\n");
  assert.deepEqual(run(...targets), ["deps:player:web-cpu", "deps:player:web-gpu"]);
  unlinkSync(resolve(root, "runtime/odin/web/new_module.odin"));
  assert.deepEqual(run(...targets), ["deps:player:web-cpu", "deps:player:web-gpu"]);
  await edit("tests/graphics/player/main_windows.odin", []);
  await edit("runtime/odin/resources/resources.odin", [
    "deps:player:web-cpu",
    "deps:player:web-gpu",
    "deps:player:native-binary",
  ]);
  await edit(".mise/toolchain.toml", all);

  for (const [name, files] of Object.entries(outputs)) {
    const missing = files.at(-1);
    unlinkSync(resolve(root, missing));
    assert.deepEqual(run(name), [name], `recover missing ${missing}`);
    for (const file of files) {
      assert.ok(existsSync(resolve(root, file)));
    }
  }
  assert.deepEqual(run(...targets), []);
});

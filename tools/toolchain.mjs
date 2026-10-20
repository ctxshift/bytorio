import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { timedSpawnSync as spawnSync } from "./command-timing.mjs";

export const repo = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const mise = process.env.MISE_BIN || "mise";
const paths = new Map();
export function run(executable, args, options = {}) {
  const result = spawnSync(executable, args, {
    cwd: repo,
    encoding: "utf8",
    timeout: 120000,
    maxBuffer: 16 * 1024 * 1024,
    ...options,
  });
  if (result.error || result.status !== 0) {
    throw new Error(
      result.error?.message ||
        result.stderr ||
        result.stdout ||
        `${executable} exited ${result.status}`,
    );
  }
  return result.stdout;
}
function lookup(command, name) {
  const key = `${command}:${name}`;
  if (!paths.has(key)) {
    paths.set(key, run(mise, [command, name]).trim());
  }
  return paths.get(key);
}
export const tool = (name) => lookup("which", name);
export const toolRoot = (name) => lookup("where", name);
export const dependencyRoot = () => resolve(toolRoot("github:bytecodealliance/wasmtime"), "lib");
export const emscriptenRoot = () => resolve(toolRoot("vfox:jdx/vfox-emsdk"), "upstream/emscripten");
export const script = (file, args = []) =>
  run(process.execPath, [resolve(repo, file), ...args], { stdio: "inherit", timeout: 600000 });
export const task = (name) => run(mise, ["run", name], { stdio: "inherit", timeout: 600000 });

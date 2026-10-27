import { constants } from "node:fs";
import {
  copyFile,
  link,
  lstat,
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  rename,
  rm,
  writeFile,
} from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { dirname, resolve, sep } from "node:path";

const marker = ".bytorio-output.json";

export async function projectDirectory(project, ...segments) {
  let path = project;
  for (const segment of segments) {
    path = resolve(path, segment);
    if (!path.startsWith(project + sep)) {
      throw new Error("Generated output escapes its project");
    }
    try {
      await mkdir(path);
    } catch (error) {
      if (error.code !== "EEXIST") {
        throw error;
      }
    }
    if (!(await lstat(path)).isDirectory()) {
      throw new Error("Generated output directories cannot be links or special files");
    }
  }
  return path;
}

export async function createBuildStage(project) {
  const parent = await projectDirectory(project, ".bytorio", "staging");
  const ignorePath = resolve(project, ".gitignore");
  let ignore = "";
  try {
    if (!(await lstat(ignorePath)).isFile()) {
      throw new Error("Generated ignore settings cannot overwrite a link or special file");
    }
    ignore = await readFile(ignorePath, "utf8");
  } catch (error) {
    if (error.code !== "ENOENT") {
      throw error;
    }
  }
  const missing = ["build/", ".bytorio/"].filter((line) => !ignore.split(/\r?\n/).includes(line));
  if (missing.length) {
    await writeFile(
      ignorePath,
      ignore + (ignore && !ignore.endsWith("\n") ? "\n" : "") + missing.join("\n") + "\n",
    );
  }
  return mkdtemp(resolve(parent, "build-"));
}

export async function removeGenerated(path) {
  await rm(path, { recursive: true, force: true, maxRetries: 3, retryDelay: 50 });
}

async function ownedBuild(path) {
  let info;
  try {
    info = await lstat(path);
  } catch (error) {
    if (error.code === "ENOENT") {
      return false;
    }
    throw error;
  }
  if (!info.isDirectory()) {
    throw new Error("Build output cannot replace a file or symlink");
  }
  try {
    const location = resolve(path, marker);
    const file = await lstat(location);
    if (!file.isFile() || file.size > 1024) {
      throw new Error("Invalid build ownership record");
    }
    const owner = JSON.parse(await readFile(location, "utf8"));
    if (owner.schema !== 1 || owner.generatedBy !== "byt") {
      throw new Error("Invalid build ownership record");
    }
  } catch (error) {
    throw new Error("Existing build directory is not owned by byt; move it before building", {
      cause: error,
    });
  }
  return true;
}

export async function publishBuild(project, stage) {
  const parent = resolve(project, ".bytorio/staging");
  if (!stage.startsWith(parent + sep) || !(await lstat(stage)).isDirectory()) {
    throw new Error("Only an owned staged build can be published");
  }
  await writeFile(
    resolve(stage, marker),
    JSON.stringify({ schema: 1, generatedBy: "byt" }) + "\n",
    {
      flag: "wx",
    },
  );
  const destination = resolve(project, "build");
  const previous = (await ownedBuild(destination))
    ? await mkdtemp(resolve(parent, "previous-"))
    : null;
  if (previous) {
    await rename(destination, resolve(previous, "build"));
  }
  try {
    await rename(stage, destination);
  } catch (error) {
    if (previous) {
      await rename(resolve(previous, "build"), destination);
      await removeGenerated(previous);
    }
    throw error;
  }
  if (previous) {
    await removeGenerated(previous);
  }
  return destination;
}

export async function copyCartridge(source, output) {
  output = resolve(output);
  if (output === resolve(source)) {
    return output;
  }
  await mkdir(dirname(output), { recursive: true });
  try {
    if (!(await lstat(output)).isFile()) {
      throw new Error("Cartridge output cannot replace a link or special file");
    }
  } catch (error) {
    if (error.code !== "ENOENT") {
      throw error;
    }
  }
  const temporary = resolve(dirname(output), `.byt-cartridge-${randomUUID()}.tmp`);
  try {
    await copyFile(source, temporary, constants.COPYFILE_EXCL);
    await rename(temporary, output);
  } finally {
    await rm(temporary, { force: true });
  }
  return output;
}

// Immutable session snapshots survive another build replacing the public output.
// Hard links reuse cartridge bytes without connecting anything to the SDK cache.
export async function snapshotWeb(project, source) {
  const parent = await projectDirectory(project, ".bytorio", "sessions");
  const destination = await mkdtemp(resolve(parent, "web-"));
  async function visit(from, to) {
    for (const entry of await readdir(from, { withFileTypes: true })) {
      const input = resolve(from, entry.name);
      const output = resolve(to, entry.name);
      if (entry.isDirectory()) {
        await mkdir(output);
        await visit(input, output);
      } else if (entry.isFile()) {
        await link(input, output);
      } else {
        throw new Error("Player snapshots cannot contain links or special files");
      }
    }
  }
  try {
    await visit(source, destination);
    return destination;
  } catch (error) {
    await removeGenerated(destination);
    throw error;
  }
}

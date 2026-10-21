import { lstat, mkdir, mkdtemp, readFile, readdir, rename, rm, writeFile } from "node:fs/promises";
import { basename, dirname, resolve, sep } from "node:path";
import { randomUUID } from "node:crypto";
import { readGltf, IMPORT_LIMITS } from "./gltf.mjs";
import { modelSources } from "./model-source.mjs";

const FILES = ["model.json", "model.luau", "model.odin"];

export async function importModel(input, output) {
  if (!output) {
    throw new Error("Model import requires --output <generated-directory>");
  }
  const target = resolve(output);
  const source = resolve(input);
  if (target === dirname(target) || source === target || source.startsWith(target + sep)) {
    throw new Error("Model output must be a dedicated directory outside the source asset");
  }
  // Validate and format everything before touching the previous generated result.
  const model = await readGltf(input);
  const files = modelSources(model);
  model.report.sourceBytes = Object.fromEntries(
    Object.entries(files).map(([name, text]) => [name, Buffer.byteLength(text)]),
  );
  if (Object.values(model.report.sourceBytes).some((size) => size > IMPORT_LIMITS.sourceBytes)) {
    throw new Error("Generated model module exceeds 128 KiB; split or simplify the asset");
  }
  files["model.json"] = JSON.stringify(model, null, 2) + "\n";
  let existing = false;
  try {
    const info = await lstat(target);
    if (!info.isDirectory() || info.isSymbolicLink()) {
      throw new Error("Model output must be a real generated directory");
    }
    const entries = await readdir(target, { withFileTypes: true });
    if (
      entries.length !== FILES.length ||
      entries.some(
        (entry) => !FILES.includes(entry.name) || !entry.isFile() || entry.isSymbolicLink(),
      )
    ) {
      throw new Error("Refusing to replace a directory containing non-generated files");
    }
    const previous = JSON.parse(await readFile(resolve(target, "model.json"), "utf8"));
    if (previous.format !== "bytorio-model" || previous.version !== 1) {
      throw new Error("Refusing to replace an unrecognized model directory");
    }
    existing = true;
  } catch (error) {
    if (error.code !== "ENOENT") {
      throw error;
    }
  }
  const parent = dirname(target);
  await mkdir(parent, { recursive: true });
  const stage = await mkdtemp(resolve(parent, `.${basename(target)}.byt-stage-`));
  const backup = resolve(parent, `.${basename(target)}.byt-backup-${randomUUID()}`);
  if (dirname(stage) !== parent || dirname(backup) !== parent) {
    throw new Error("Invalid model staging paths");
  }
  let backedUp = false;
  let published = false;
  try {
    for (const [name, text] of Object.entries(files)) {
      await writeFile(resolve(stage, name), text, { flag: "wx" });
    }
    if (existing) {
      await rename(target, backup);
      backedUp = true;
    }
    await rename(stage, target);
    published = true;
  } catch (error) {
    if (backedUp && !published) {
      try {
        await rename(backup, target);
        backedUp = false;
      } catch (recovery) {
        throw new Error(
          `Model publication failed (${error.message}) and recovery failed; previous files retained at ${basename(backup)}: ${recovery.message}`,
          { cause: recovery },
        );
      }
    }
    throw error;
  } finally {
    // Both recursive targets are verified siblings created by this operation.
    await rm(stage, { recursive: true, force: true });
    if (published && backedUp) {
      await rm(backup, { recursive: true });
    }
  }
  return model;
}

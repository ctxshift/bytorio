import { access, copyFile, mkdir, readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { createProject, buildProject } from "./sdk/project.mjs";
import { importModel } from "./sdk/import-model.mjs";
import { readGltf } from "./sdk/gltf.mjs";
import { modelSources } from "./sdk/model-source.mjs";

export async function checkModelExamples(write = false) {
  const sources = modelSources(await readGltf("tests/models/rigid-kart.gltf"));
  for (const language of ["luau", "odin"]) {
    const directory = `examples/model-${language}/imported`;
    const path = `${directory}/model.${language}`;
    const source = sources[`model.${language}`];
    if (write) {
      await mkdir(directory, { recursive: true });
      await writeFile(path, source);
    } else if ((await readFile(path, "utf8")) !== source) {
      throw new Error(`Generated model example is stale: ${path}; run mise run generate:models`);
    }
  }
}

export async function buildModels(root = "build/models", input = "tests/models/rigid-kart.gltf") {
  await checkModelExamples();
  await mkdir(root, { recursive: true });
  const projects = [];
  for (const language of ["odin", "luau"]) {
    const project = resolve(root, language);
    try {
      await access(resolve(project, "console.json"));
    } catch {
      await createProject(project, language);
    }
    const imported = await importModel(input, resolve(project, "src/imported"));
    const manifest = JSON.parse(await readFile(resolve(project, "console.json")));
    Object.assign(manifest, {
      sdk: imported.minimumSdk,
      profile: imported.profile,
      display: [320, 180],
      title: `Imported rigid model / ${language}`,
    });
    await writeFile(resolve(project, "console.json"), JSON.stringify(manifest, null, 2) + "\n");
    await copyFile(
      `examples/model-${language}/main.${language}`,
      resolve(project, `src/main.${language}`),
    );
    await buildProject(project);
    projects.push({ language, project });
  }
  await copyFile("tests/models/index.html", resolve(root, "index.html"));
  await copyFile("tests/models/index.html", resolve(root, "player.html"));
  return projects;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  if (process.argv.includes("--update-examples")) {
    await checkModelExamples(true);
  } else {
    await buildModels();
  }
}

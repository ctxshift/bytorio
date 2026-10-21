import { access, copyFile, mkdir, readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { createProject, buildProject } from "./sdk/project.mjs";

export async function buildTexturedDrawing(root) {
  await mkdir(root, { recursive: true });
  const projects = [];
  for (const language of ["odin", "luau"]) {
    const project = resolve(root, language);
    try {
      await access(resolve(project, "console.json"));
    } catch {
      await createProject(project, language);
    }
    const manifest = JSON.parse(await readFile(resolve(project, "console.json")));
    Object.assign(manifest, {
      sdk: "0.4.0",
      profile: "textured-3d-preview-1",
      display: [320, 180],
    });
    await writeFile(resolve(project, "console.json"), JSON.stringify(manifest, null, 2));
    await copyFile(
      `tests/textured3d/drawing/main.${language}`,
      resolve(project, `src/main.${language}`),
    );
    await buildProject(project);
    projects.push({ language, project });
  }
  return projects;
}

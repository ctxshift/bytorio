import { access, copyFile, mkdir, readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { createProject, buildProject } from "./sdk/project.mjs";

// Stable, reproducible example exports; edit the checked-in cartridge sources.
export async function buildResourceExamples(root = "build/resource-profile") {
  await mkdir(root, { recursive: true });
  const projects = [];
  for (const demo of ["graphics", "synthesis"]) {
    for (const language of ["luau", "odin"]) {
      const project = resolve(root, `${demo}-${language}`);
      try {
        await access(resolve(project, "console.json"));
      } catch {
        await createProject(project, language);
      }
      const manifest = JSON.parse(await readFile(resolve(project, "console.json")));
      Object.assign(manifest, {
        sdk: "0.2.0",
        profile: "resource-av-1",
        display: [320, 180],
        title: `${demo} / ${language}`,
      });
      await writeFile(resolve(project, "console.json"), JSON.stringify(manifest, null, 2) + "\n");
      await copyFile(
        `tests/${demo}/cartridges/game.${language}`,
        resolve(project, `src/main.${language}`),
      );
      await buildProject(project);
      projects.push({ project, demo, language });
    }
  }
  return projects;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  await buildResourceExamples();
}

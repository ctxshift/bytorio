import { access, copyFile, mkdir, readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { createProject, buildProject } from "../../../tools/sdk/project.mjs";

export async function buildBillboards(root = "examples/billboards/build") {
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
      sdk: "0.5.0",
      profile: "alpha-3d-preview-1",
      display: [320, 180],
      title: `Billboard Garden / ${language}`,
    });
    await writeFile(resolve(project, "console.json"), JSON.stringify(manifest, null, 2));
    await copyFile(
      `examples/billboards/${language}/main.${language}`,
      resolve(project, `src/main.${language}`),
    );
    await buildProject(project);
    projects.push({ language, project });
  }
  await copyFile("examples/billboards/index.html", resolve(root, "index.html"));
  await copyFile("examples/billboards/index.html", resolve(root, "player.html"));
  return projects;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  await buildBillboards();
}

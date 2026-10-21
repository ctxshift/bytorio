import { access, copyFile, cp, mkdir, readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { generateCourse } from "./course.mjs";
import { importKart } from "./import-assets.mjs";
import { generateAssets } from "./assets.mjs";
import { createProject, buildProject } from "../../../tools/sdk/project.mjs";

export const root = "examples/kart3d/build";
export async function buildKart3d() {
  await mkdir(root, { recursive: true });
  await generateCourse(process.argv.includes("--generate"));
  await importKart();
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
      sdk: "0.6.0",
      profile: "effects-3d-preview-1",
      display: [320, 180],
      title: `Sunline Sprint / ${language}`,
    });
    await writeFile(resolve(project, "console.json"), JSON.stringify(manifest, null, 2) + "\n");
    await cp(`examples/kart3d/${language}`, resolve(project, "src"), { recursive: true });
    await buildProject(project);
    for (const host of ["web"]) {
      const file = resolve(project, "build", host, "player.html");
      let html = await readFile(file, "utf8");
      html = html.replace(
        "</head>",
        "<style>#performance { position: static; display: block; margin: 12px auto; max-width: 700px; } #screen:fullscreen #performance { display: none; }</style>\n</head>",
      );
      html = html.replace('<output id="performance">Waiting for frames…</output>', "");
      html = html.replace(
        '<button id="start" disabled>',
        '<output id="performance">Waiting for frames…</output>\n<button id="start" disabled>',
      );
      html = html.replace(
        '<script type="module" src="./player.js"></script>',
        '<script>globalThis.playerInstructions="WASD/arrows: drive · Space: hop/drift · E: turbo · Q: resolution · Space+Q: auto/low/high detail · R: restart";</script>\n<script type="module" src="./player.js"></script>',
      );
      await writeFile(file, html);
    }
    projects.push({ language, project });
  }
  await mkdir(root, { recursive: true });
  await copyFile("examples/kart3d/shared/index.html", resolve(root, "index.html"));
  await copyFile("examples/kart3d/shared/index.html", resolve(root, "player.html"));
  return projects;
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  if (process.argv.includes("--generate")) {
    await generateCourse(true);
    await generateAssets();
    await importKart(true);
  } else {
    await buildKart3d();
  }
}

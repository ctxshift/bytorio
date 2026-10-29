import { createHash } from "node:crypto";
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { games } from "../site/catalog.mjs";
import { repo, run } from "./toolchain.mjs";

// Receipts reuse exported artifacts, never test results. Include every exported
// byte so a partial copy or local player override cannot masquerade as the pin.
export async function exportDigest(directory) {
  const hash = createHash("sha256");
  async function visit(relative = "") {
    const entries = await readdir(resolve(directory, relative), { withFileTypes: true });
    entries.sort((a, b) => a.name.localeCompare(b.name, "en"));
    for (const entry of entries) {
      const name = relative ? `${relative}/${entry.name}` : entry.name;
      if (entry.isDirectory()) {
        await visit(name);
      } else if (entry.isFile()) {
        hash.update(name + "\0");
        hash.update(
          createHash("sha256")
            .update(await readFile(resolve(directory, name)))
            .digest(),
        );
      } else {
        throw new Error("Showcase exports must contain regular files and directories");
      }
    }
  }
  await visit();
  return hash.digest("hex");
}

export async function reusableExport(checkout, revision) {
  try {
    const receipt = JSON.parse(
      await readFile(resolve(checkout, "build/showcase-export.json"), "utf8"),
    );
    for (const name of ["game.png", "player.html", "runtime.js", "web-player.js"]) {
      if (!existsSync(resolve(checkout, "build/web", name))) {
        return false;
      }
    }
    return (
      receipt.schema === 1 &&
      receipt.revision === revision &&
      receipt.digest === (await exportDigest(resolve(checkout, "build/web")))
    );
  } catch (error) {
    if (error.code === "ENOENT" || error instanceof SyntaxError) {
      return false;
    }
    throw error;
  }
}

export async function prepareShowcase({ force = false } = {}) {
  for (const game of games) {
    const checkout = resolve(repo, game.build);
    await mkdir(checkout, { recursive: true });
    if (!existsSync(resolve(checkout, ".git"))) {
      run("git", ["init", checkout]);
    }
    const head = spawnSync("git", ["rev-parse", "--verify", "HEAD"], {
      cwd: checkout,
      encoding: "utf8",
    });
    if (head.status === 0) {
      const git = (args) => execFileSync("git", args, { cwd: checkout, encoding: "utf8" });
      const edited = [
        ...git(["diff", "--name-only", "-z", "HEAD", "--"]).split("\0"),
        ...git(["ls-files", "--others", "--exclude-standard", "-z"]).split("\0"),
      ]
        // SDK authoring refreshes this local analyzer resolver during builds.
        .filter((file) => file && file !== ".luaurc");
      if (edited.length) {
        throw new Error(
          `Showcase checkout has local source edits: ${game.build}. Preserve or resolve them before rebuilding.`,
        );
      }
      if (
        !force &&
        head.stdout.trim() === game.revision &&
        (await reusableExport(checkout, game.revision))
      ) {
        console.log(`Reusing showcase export: ${game.title} at ${game.revision}`);
        continue;
      }
    }
    run("git", ["fetch", "--depth=1", game.repository, game.revision], { cwd: checkout });
    run("git", ["checkout", "--detach", "FETCH_HEAD"], { cwd: checkout });
    const mise = process.env.MISE_BIN || "mise";
    console.log(`Preparing showcase: ${game.title} at ${game.revision}`);
    run(mise, ["trust"], { cwd: checkout });
    run(mise, ["install"], { cwd: checkout, timeout: 1800000 });
    run(mise, ["exec", "--", "byt", "build", "--target", "web"], {
      cwd: checkout,
      timeout: 1800000,
    });
    await writeFile(
      resolve(checkout, "build/showcase-export.json"),
      JSON.stringify({
        schema: 1,
        revision: game.revision,
        digest: await exportDigest(resolve(checkout, "build/web")),
      }) + "\n",
    );
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await prepareShowcase();
}

import assert from "node:assert/strict";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { readGltf } from "../../../tools/sdk/gltf.mjs";
import { modelSources } from "../../../tools/sdk/model-source.mjs";
import { formatSource } from "../../../tools/code-tools.mjs";

export async function importKart(write = false) {
  const base = "examples/kart3d";
  const model = await readGltf(`${base}/assets/kart-lod.gltf`);
  const low = await readGltf(`${base}/assets/kart-low.gltf`);
  const high = await readGltf(`${base}/assets/kart-high.gltf`);
  assert.deepEqual(
    low.nodes.map(({ name, local, parent }) => ({ name, local, parent })),
    high.nodes.map(({ name, local, parent }) => ({ name, local, parent })),
  );
  assert.deepEqual(
    model.nodes.map(({ name }) => name),
    [
      "body",
      "driver",
      "cape",
      "wheel_front_left",
      "wheel_front_right",
      "wheel_rear_left",
      "wheel_rear_right",
      "body_detail",
      "driver_detail",
      "wheel_high",
    ],
  );
  assert.deepEqual(
    model.nodes.map(({ primitives }) => primitives),
    [[0], [1], [2], [3], [3], [3], [3], [4], [5], [6]],
  );
  const sources = modelSources(model);
  for (const primitive of model.primitives) {
    const material = model.materials[primitive.material];
    for (let at = 0; at < primitive.indices.length; at += 3) {
      const triangle = primitive.indices
        .slice(at, at + 3)
        .map((index) => primitive.vertices[index]);
      if (triangle.every(({ uv }) => uv[0] === triangle[0].uv[0] && uv[1] === triangle[0].uv[1])) {
        assert.equal(
          (triangle[0].uv[0] * material.width) % 1,
          0.5,
          "Solid paint samples a texel center on U",
        );
        assert.equal(
          (triangle[0].uv[1] * material.height) % 1,
          0.5,
          "Solid paint samples a texel center on V",
        );
      }
    }
  }
  const tree = modelSources(await readGltf(`${base}/assets/tree.gltf`));
  const colors = Buffer.from(model.materials[0].pixels);
  const atlas = Array.from(
    { length: colors.length / 4 },
    (_, index) =>
      `0x${colors
        .readUInt32LE(index * 4)
        .toString(16)
        .padStart(8, "0")}`,
  );
  for (const language of ["odin", "luau"]) {
    const directory = `${base}/${language}/imported`;
    const path = `${directory}/model.${language}`;
    if (write) {
      await mkdir(directory, { recursive: true });
      await writeFile(path, sources[`model.${language}`]);
    } else {
      assert.equal(
        await readFile(path, "utf8"),
        sources[`model.${language}`],
        "Kart import is stale; run the example generate task",
      );
    }
    const treeDirectory = `${base}/${language}/tree`;
    const treePath = `${treeDirectory}/model.${language}`;
    const palettePath = `${base}/${language}/atlas.${language}`;
    const paletteSource = formatSource(
      language === "luau"
        ? `--!strict\n-- Generated from the kart's imported atlas.\nreturn {${atlas}}\n`
        : `// Generated from the kart's imported atlas.\npackage main\nKART_ATLAS := [256]u32{${atlas}}\n`,
      palettePath,
    );
    if (write) {
      await mkdir(treeDirectory, { recursive: true });
      await writeFile(treePath, tree[`model.${language}`]);
      await writeFile(palettePath, paletteSource);
    } else {
      assert.equal(
        await readFile(treePath, "utf8"),
        tree[`model.${language}`],
        "Tree import is stale",
      );
      assert.equal(await readFile(palettePath, "utf8"), paletteSource, "Kart atlas is stale");
    }
  }
  return model;
}

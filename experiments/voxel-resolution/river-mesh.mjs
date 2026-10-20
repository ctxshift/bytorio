import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

const VERTEX_BYTES = 16;
const TERRAIN_EXTENT = 160;
const RABBIT_ORIGIN = [-4, 8, 19];
const EXPLICIT_AIR = 65535;
const FACES = [
  {
    axis: 0,
    sign: -1,
    corners: [
      [0, 0, 0],
      [0, 0, 1],
      [0, 1, 1],
      [0, 1, 0],
    ],
  },
  {
    axis: 0,
    sign: 1,
    corners: [
      [1, 0, 1],
      [1, 0, 0],
      [1, 1, 0],
      [1, 1, 1],
    ],
  },
  {
    axis: 1,
    sign: -1,
    corners: [
      [0, 0, 1],
      [0, 0, 0],
      [1, 0, 0],
      [1, 0, 1],
    ],
  },
  {
    axis: 1,
    sign: 1,
    corners: [
      [0, 1, 0],
      [0, 1, 1],
      [1, 1, 1],
      [1, 1, 0],
    ],
  },
  {
    axis: 2,
    sign: -1,
    corners: [
      [1, 0, 0],
      [0, 0, 0],
      [0, 1, 0],
      [1, 1, 0],
    ],
  },
  {
    axis: 2,
    sign: 1,
    corners: [
      [0, 0, 1],
      [1, 0, 1],
      [1, 1, 1],
      [0, 1, 1],
    ],
  },
];

function mesh(getVoxel, shade, bounds, origin = [0, 0, 0]) {
  let bytes = Buffer.alloc(8 * 1024 * 1024);
  let size = 0;
  for (let z = bounds[2][0]; z < bounds[2][1]; z++) {
    for (let x = bounds[0][0]; x < bounds[0][1]; x++) {
      const ceiling = Math.abs(x) < 96 && Math.abs(z) < 96 ? bounds[1][1] : 15;
      for (let y = bounds[1][0]; y < ceiling; y++) {
        const material = getVoxel(x, y, z);
        if (!material) {
          continue;
        }
        for (const face of FACES) {
          if (y === 0 && face.axis === 1 && face.sign === -1) {
            continue;
          }
          const neighbor = [x, y, z];
          neighbor[face.axis] += face.sign;
          if (getVoxel(...neighbor)) {
            continue;
          }
          const rgb = shade({ p: [x, y, z], axis: face.axis, sign: face.sign, material });
          if (size + 6 * VERTEX_BYTES > bytes.length) {
            const bigger = Buffer.alloc(bytes.length * 2);
            bytes.copy(bigger);
            bytes = bigger;
          }
          for (const corner of [0, 1, 2, 0, 2, 3]) {
            const p = face.corners[corner];
            bytes.writeFloatLE(x + p[0] - origin[0], size);
            bytes.writeFloatLE(y + p[1] - origin[1], size + 4);
            bytes.writeFloatLE(z + p[2] - origin[2], size + 8);
            bytes.set([...rgb, 255], size + 12);
            size += VERTEX_BYTES;
          }
        }
      }
    }
  }
  return bytes.subarray(0, size);
}

export async function buildLiveAssets(scene) {
  const { output, voxel, shade, terrainColumn, props, rabbitProps, propIndex } = scene;
  scene.setRabbitVisible(false);
  const world = mesh(voxel, shade, [
    [-TERRAIN_EXTENT, TERRAIN_EXTENT],
    [0, 56],
    [-TERRAIN_EXTENT, TERRAIN_EXTENT],
  ]);
  await writeFile(join(output, "world.bin"), world);
  scene.setRabbitVisible(true);
  const rabbitVoxel = (x, y, z) => {
    if (x < -95 || x > 95 || z < -95 || z > 95 || y < 0 || y >= 80) {
      return 0;
    }
    return rabbitProps[propIndex(x, y, z)];
  };
  const rabbit = mesh(
    rabbitVoxel,
    shade,
    [
      [-13, 5],
      [8, 42],
      [13, 27],
    ],
    RABBIT_ORIGIN,
  );
  await writeFile(join(output, "rabbit.bin"), rabbit);
  scene.setRabbitVisible(false);
  const walk = { minX: -78, maxX: 78, minZ: -68, maxZ: 68, heights: [] };
  for (let z = walk.minZ; z <= walk.maxZ; z++) {
    for (let x = walk.minX; x <= walk.maxX; x++) {
      const column = terrainColumn(x, z);
      const onBridge = x >= 14 && x <= 42 && z >= 14 && z <= 23;
      let height = onBridge
        ? 10 + Math.round(4 * Math.sin(((x - 14) / 28) * Math.PI))
        : column.top + 1;
      if (column.isWater && !onBridge) {
        height = -1;
      }
      if (height >= 0) {
        for (let y = height; y < height + 31; y++) {
          const material = props[propIndex(x, y, z)];
          if (material && material !== EXPLICIT_AIR) {
            height = -1;
            break;
          }
        }
      }
      walk.heights.push(height);
    }
  }
  const start = walk.heights[(19 - walk.minZ) * (walk.maxX - walk.minX + 1) - 4 - walk.minX];
  assert(start >= 0, "Rabbit must start on walkable ground");
  await writeFile(
    join(output, "live-scene.json"),
    JSON.stringify({
      camera: scene.camera,
      rabbitOrigin: RABBIT_ORIGIN,
      vertexBytes: VERTEX_BYTES,
      worldVertices: world.length / VERTEX_BYTES,
      rabbitVertices: rabbit.length / VERTEX_BYTES,
      terrainExtent: TERRAIN_EXTENT,
      walk,
      lighting: "Baked per-face shadows and local occlusion; rabbit moves independently",
    }),
  );
  for (const file of ["river-live.js"]) {
    await writeFile(join(output, file), await readFile(new URL(file, import.meta.url)));
  }
  console.log(
    `Live scene: ${world.length / VERTEX_BYTES} world vertices; ${rabbit.length / VERTEX_BYTES} rabbit vertices.`,
  );
}

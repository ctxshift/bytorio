import { mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { deflateSync } from "node:zlib";
import { chunk, signature } from "../../../tools/sdk/cartridge.mjs";

const assetDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "../assets");
const atlasSize = 16;
const tileSize = 4;
const paint = Object.freeze({
  red: 0,
  redShade: 1,
  charcoal: 2,
  steel: 3,
  tire: 4,
  purple: 5,
  purpleShade: 6,
  skin: 7,
  ivory: 8,
  gold: 9,
  leaf: 10,
  leafShade: 11,
  bark: 12,
  stone: 13,
  hub: 14,
  asphalt: 15,
});
const palette = [
  [224, 47, 35],
  [153, 27, 34],
  [35, 39, 48],
  [150, 169, 178],
  [31, 32, 37],
  [102, 51, 197],
  [63, 30, 128],
  [240, 176, 118],
  [244, 235, 200],
  [255, 191, 45],
  [100, 169, 39],
  [53, 114, 32],
  [108, 70, 40],
  [174, 169, 145],
  [178, 190, 194],
  [107, 109, 113],
];

function atlas() {
  const rows = Buffer.alloc(atlasSize * (atlasSize * 4 + 1));
  for (let y = 0; y < atlasSize; y++) {
    for (let x = 0; x < atlasSize; x++) {
      const tile = Math.floor(x / tileSize) + Math.floor(y / tileSize) * 4;
      const u = x % tileSize;
      const v = y % tileSize;
      let shade;
      if (tile === paint.tire) {
        shade = (u + v * 2) % 5 < 2 ? 1.4 : 0.86;
      } else if (tile === paint.stone) {
        shade = v % 4 === 0 || (u + (v < 4 ? 0 : 4)) % 8 === 0 ? 0.68 : 1;
      } else if (tile === paint.bark) {
        shade = u % 3 === 0 ? 0.7 : 1.08;
      } else if (tile === paint.asphalt) {
        shade = 0.91 + ((u * 11 + v * 7 + u * v) % 7) * 0.025;
      } else if (tile === paint.leaf || tile === paint.leafShade) {
        shade = (u + v * 3) % 7 < 2 ? 1.12 : 0.97;
      } else if (tile === paint.hub) {
        shade = u > 0 && u < 3 && v > 0 && v < 3 ? 1 : 0.2;
      } else {
        shade = v === 1 ? 1.12 : v > 5 ? 0.89 : 1;
      }
      const offset = y * (atlasSize * 4 + 1) + 1 + x * 4;
      for (let channel = 0; channel < 3; channel++) {
        rows[offset + channel] = Math.min(255, Math.round(palette[tile][channel] * shade));
      }
      rows[offset + 3] = 255;
    }
  }
  const header = Buffer.alloc(13);
  header.writeUInt32BE(atlasSize, 0);
  header.writeUInt32BE(atlasSize, 4);
  header[8] = 8;
  header[9] = 6;
  return Buffer.concat([
    signature,
    chunk("IHDR", header),
    chunk("IDAT", deflateSync(rows)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

// Author in the game's +Z-forward frame, on a 1/64-unit grid. The glTF writer
// reflects Z and reverses winding; the importer restores the authored frame.
const snap = (value) => Math.round(value * 64) / 64;
const point = (values) => values.map(snap);

class Mesh {
  positions = [];
  uv = [];
  indices = [];
  vertices = new Map();

  face(corners, tile, inset = 0.5, localUV = null) {
    const left = ((tile % 4) * tileSize + inset) / atlasSize;
    const right = ((tile % 4) * tileSize + tileSize - inset) / atlasSize;
    const top = (Math.floor(tile / 4) * tileSize + inset) / atlasSize;
    const bottom = (Math.floor(tile / 4) * tileSize + tileSize - inset) / atlasSize;
    const textured = [paint.tire, paint.stone, paint.bark, paint.hub, paint.asphalt].includes(tile);
    const mapping =
      localUV ??
      (textured
        ? [
            [0, 1],
            [1, 1],
            [1, 0],
            [0, 0],
          ]
        : [
            [0.5, 0.5],
            [0.5, 0.5],
            [0.5, 0.5],
            [0.5, 0.5],
          ]);
    // Solid faces sample a texel center, never a boundary between two texels.
    // Perspective interpolation can round a boundary to either neighbor on
    // different GPU drivers, producing speckling even when UVs are constant.
    const centerU = ((tile % 4) * tileSize + Math.floor(tileSize / 2) + 0.5) / atlasSize;
    const centerV = (Math.floor(tile / 4) * tileSize + Math.floor(tileSize / 2) + 0.5) / atlasSize;
    const coordinates =
      !textured && localUV === null
        ? corners.map(() => [centerU, centerV])
        : mapping.map(([u, v]) => [left + (right - left) * u, top + (bottom - top) * v]);
    const ids = corners.map((corner, index) => {
      const position = point(corner);
      const uv = coordinates[index].map((value) => Math.round(value * 256) / 256);
      const key = [...position, ...uv].join(",");
      if (!this.vertices.has(key)) {
        this.vertices.set(key, this.positions.length / 3);
        this.positions.push(position[0], position[1], -position[2]);
        this.uv.push(...uv);
      }
      return this.vertices.get(key);
    });
    for (let index = 1; index < ids.length - 1; index++) {
      this.indices.push(ids[0], ids[index + 1], ids[index]);
    }
  }

  box(x, y, z, width, height, depth, tile, bottom = false) {
    const a = x - width / 2;
    const b = x + width / 2;
    const c = z - depth / 2;
    const d = z + depth / 2;
    const t = y + height;
    this.face(
      [
        [a, t, c],
        [a, t, d],
        [b, t, d],
        [b, t, c],
      ],
      tile,
    );
    this.face(
      [
        [a, y, c],
        [b, y, c],
        [b, t, c],
        [a, t, c],
      ],
      tile,
    );
    this.face(
      [
        [b, y, d],
        [a, y, d],
        [a, t, d],
        [b, t, d],
      ],
      tile,
    );
    this.face(
      [
        [a, y, d],
        [a, y, c],
        [a, t, c],
        [a, t, d],
      ],
      tile,
    );
    this.face(
      [
        [b, y, c],
        [b, y, d],
        [b, t, d],
        [b, t, c],
      ],
      tile,
    );
    if (bottom) {
      this.face(
        [
          [a, y, c],
          [a, y, d],
          [b, y, d],
          [b, y, c],
        ],
        tile,
      );
    }
  }

  crown(x, y, z, width, height, depth, tile, sides = 6) {
    for (let side = 0; side < sides; side++) {
      const angle = (side * Math.PI * 2) / sides;
      const next = ((side + 1) * Math.PI * 2) / sides;
      const a = [
        x + (Math.cos(angle) * width) / 2,
        y + height * 0.4,
        z + (Math.sin(angle) * depth) / 2,
      ];
      const b = [
        x + (Math.cos(next) * width) / 2,
        y + height * 0.4,
        z + (Math.sin(next) * depth) / 2,
      ];
      this.face([a, [x, y + height, z], b], tile);
      this.face([b, [x, y, z], a], tile);
    }
  }

  spike(base, tip, width, depth, tile) {
    const [x, y, z] = base;
    const ring = [
      [x - width / 2, y, z - depth / 2],
      [x - width / 2, y, z + depth / 2],
      [x + width / 2, y, z + depth / 2],
      [x + width / 2, y, z - depth / 2],
    ];
    for (let side = 0; side < 4; side++) {
      this.face([ring[side], tip, ring[(side + 1) % 4]], tile);
    }
  }
}

function kartBody() {
  const mesh = new Mesh();
  const outline = [
    [-0.58, -1.14],
    [-0.78, -0.91],
    [-0.78, 0.72],
    [-0.54, 1.22],
    [0.54, 1.22],
    [0.78, 0.72],
    [0.78, -0.91],
    [0.58, -1.14],
  ];
  for (let side = 0; side < outline.length; side++) {
    const [x, z] = outline[side];
    const [nx, nz] = outline[(side + 1) % outline.length];
    mesh.face(
      [
        [x, 0.25, z],
        [nx, 0.25, nz],
        [nx, 0.48, nz],
        [x, 0.48, z],
      ],
      paint.redShade,
    );
    mesh.face(
      [
        [x, 0.48, z],
        [nx, 0.48, nz],
        [nx * 0.84, 0.63, nz * 0.9],
        [x * 0.84, 0.63, z * 0.9],
      ],
      paint.red,
    );
  }
  // The long cream hood stripe, raised cockpit and split rear bumper read from
  // the chase camera even at 320×180. Hidden bottoms are intentionally omitted.
  mesh.box(0, 0.48, 0.72, 1.16, 0.25, 0.75, paint.red);
  mesh.face(
    [
      [-0.12, 0.75, 0.35],
      [-0.12, 0.75, 1.1],
      [0.12, 0.75, 1.1],
      [0.12, 0.75, 0.35],
    ],
    paint.ivory,
  );
  mesh.box(0, 0.52, -0.49, 0.77, 0.51, 0.24, paint.charcoal);
  mesh.box(0, 0.48, -0.92, 0.7, 0.34, 0.36, paint.steel);
  mesh.face(
    [
      [-0.28, 0.83, -1.05],
      [-0.28, 0.83, -0.77],
      [0.28, 0.83, -0.77],
      [0.28, 0.83, -1.05],
    ],
    paint.charcoal,
  );
  mesh.box(0, 0.23, -1.2, 1.65, 0.2, 0.22, paint.charcoal);
  mesh.face(
    [
      [-0.43, 0.28, -1.33],
      [0.43, 0.28, -1.33],
      [0.43, 0.51, -1.33],
      [-0.43, 0.51, -1.33],
    ],
    paint.red,
  );
  mesh.face(
    [
      [-0.24, 0.31, -1.34],
      [0.24, 0.31, -1.34],
      [0.24, 0.42, -1.34],
      [-0.24, 0.42, -1.34],
    ],
    paint.ivory,
  );
  for (const side of [-1, 1]) {
    mesh.box(side * 0.53, 0.56, -0.96, 0.17, 0.17, 0.53, paint.steel);
    mesh.face(
      [
        [side * 0.53 - 0.06, 0.58, -1.24],
        [side * 0.53 + 0.06, 0.58, -1.24],
        [side * 0.53 + 0.06, 0.7, -1.24],
        [side * 0.53 - 0.06, 0.7, -1.24],
      ],
      paint.charcoal,
    );
    mesh.face(
      [
        [side * 0.68, 0.46, -0.86],
        [side * 0.68, 0.46, 0.48],
        [side * 0.56, 0.72, 0.48],
        [side * 0.56, 0.72, -0.86],
      ],
      paint.red,
    );
    mesh.face(
      [
        [side * 0.56, 0.5, -1.16],
        [side * 0.72, 0.5, -1.16],
        [side * 0.72, 0.63, -1.16],
        [side * 0.56, 0.63, -1.16],
      ],
      paint.gold,
    );
  }
  return mesh;
}

function driver() {
  const mesh = new Mesh();
  mesh.box(0, 0.73, -0.15, 0.59, 0.57, 0.41, paint.purpleShade);
  mesh.crown(0, 1.29, -0.13, 0.72, 0.67, 0.68, paint.skin, 6);
  // Sculpted hair silhouette: broad asymmetric locks instead of a smooth helmet.
  mesh.crown(0, 1.49, -0.25, 1.02, 0.66, 0.96, paint.purple, 7);
  const locks = [
    [[-0.32, 1.78, -0.22], [-0.76, 2.02, -0.27], 0.43, 0.42],
    [[0.3, 1.78, -0.17], [0.7, 2.16, -0.13], 0.44, 0.46],
    [[-0.13, 1.98, -0.19], [-0.31, 2.43, -0.13], 0.4, 0.44],
    [[0.19, 1.98, -0.3], [0.4, 2.34, -0.49], 0.43, 0.41],
    [[0, 1.8, -0.57], [-0.08, 2.05, -0.93], 0.58, 0.39],
  ];
  for (const [base, tip, width, depth] of locks) {
    mesh.spike(base, tip, width, depth, paint.purple);
  }
  for (const side of [-1, 0, 1]) {
    mesh.face(
      [
        [side * 0.24 - 0.24, 1.83, -0.53],
        [side * 0.3, 1.34, -0.48],
        [side * 0.24 + 0.24, 1.83, -0.53],
      ],
      paint.purpleShade,
    );
  }
  for (const side of [-1, 1]) {
    mesh.face(
      [
        [side * 0.24, 1.22, 0],
        [side * 0.5, 0.97, 0.46],
        [side * 0.4, 0.88, 0.55],
        [side * 0.13, 1.09, 0.08],
      ],
      paint.skin,
    );
    mesh.face(
      [
        [side * 0.22, 1.29, -0.13],
        [side * 0.43, 1.12, 0.13],
        [side * 0.34, 1.02, 0.22],
        [side * 0.12, 1.18, 0.02],
      ],
      paint.ivory,
    );
  }
  mesh.face(
    [
      [-0.36, 0.94, 0.48],
      [0.36, 0.94, 0.48],
      [0.29, 1.04, 0.38],
      [-0.29, 1.04, 0.38],
    ],
    paint.charcoal,
  );
  return mesh;
}

function cape() {
  const mesh = new Mesh();
  // Local origin is the neck. Three folded panels trail behind the kart and
  // remain a single rigid draw that the game can yaw or flutter independently.
  const neckLeft = [-0.28, 0, 0];
  const neckRight = [0.28, 0, 0];
  const ridge = [0.03, -0.35, -0.63];
  const left = [-0.73, -0.51, -1.04];
  const right = [0.63, -0.61, -1.12];
  const tail = [-0.13, -0.76, -1.36];
  mesh.face([neckLeft, left, ridge], paint.red);
  mesh.face([neckRight, neckLeft, ridge], paint.red);
  mesh.face([neckRight, ridge, right], paint.redShade);
  mesh.face([left, tail, ridge], paint.redShade);
  mesh.face([ridge, tail, right], paint.red);
  return mesh;
}

function wheel(sides = 8, radius = 0.39, halfWidth = 0.23) {
  const mesh = new Mesh();
  for (let side = 0; side < sides; side++) {
    const angle = (side * Math.PI * 2) / sides;
    const next = ((side + 1) * Math.PI * 2) / sides;
    const y = Math.sin(angle) * radius;
    const z = Math.cos(angle) * radius;
    const ny = Math.sin(next) * radius;
    const nz = Math.cos(next) * radius;
    mesh.face(
      [
        [-halfWidth, y, z],
        [halfWidth, y, z],
        [halfWidth, ny, nz],
        [-halfWidth, ny, nz],
      ],
      paint.tire,
    );
    for (const end of [-1, 1]) {
      const x = end * halfWidth;
      mesh.face(
        [
          [x, 0, 0],
          [x, y, z],
          [x, ny, nz],
        ],
        paint.hub,
        0.5,
        [
          [0.5, 0.5],
          [0.5 + y / (2 * radius), 0.5 + z / (2 * radius)],
          [0.5 + ny / (2 * radius), 0.5 + nz / (2 * radius)],
        ],
      );
    }
  }
  return mesh;
}

function tree() {
  const mesh = new Mesh();
  mesh.box(0, 0, 0, 0.42, 2, 0.42, paint.bark);
  mesh.crown(0, 1.13, 0, 3.2, 3.1, 2.9, paint.leaf, 7);
  mesh.crown(-0.72, 1.65, -0.15, 1.9, 2, 1.85, paint.leafShade, 5);
  mesh.crown(0.7, 1.8, 0.1, 1.8, 2, 1.9, paint.leaf, 5);
  return mesh;
}

function bodyDetail() {
  const mesh = new Mesh();
  // Engine cooling fins and a slim seat hoop are visible above the rear shell.
  for (const z of [-1.02, -0.94, -0.86, -0.78]) {
    mesh.box(0, 0.84, z, 0.59, 0.045, 0.035, paint.steel);
  }
  for (const side of [-1, 1]) {
    mesh.box(side * 0.39, 0.73, -0.58, 0.07, 0.54, 0.07, paint.steel);
    mesh.box(side * 0.69, 0.28, 0.3, 0.12, 0.08, 1.34, paint.charcoal);
    mesh.box(side * 0.48, 0.37, -1.26, 0.12, 0.24, 0.12, paint.red);
  }
  mesh.box(0, 1.22, -0.58, 0.85, 0.07, 0.07, paint.steel);
  // A real open steering rim replaces the low model's broad steering bar.
  for (let side = 0; side < 8; side++) {
    const angle = (side * Math.PI) / 4;
    const next = ((side + 1) * Math.PI) / 4;
    const rim = (a, scale) => [
      Math.sin(a) * 0.35 * scale,
      1.02 + Math.cos(a) * 0.1 * scale,
      0.43 + Math.cos(a) * 0.2 * scale,
    ];
    mesh.face([rim(angle, 1), rim(next, 1), rim(next, 0.76), rim(angle, 0.76)], paint.charcoal);
  }
  return mesh;
}

function driverDetail() {
  const mesh = new Mesh();
  for (const side of [-1, 1]) {
    mesh.box(side * 0.39, 0.9, 0.43, 0.17, 0.15, 0.2, paint.ivory);
    mesh.spike([side * 0.38, 1.79, -0.25], [side * 0.69, 1.52, -0.36], 0.29, 0.36, paint.purple);
    mesh.face(
      [
        [side * 0.17 - 0.045, 1.59, 0.24],
        [side * 0.17 + 0.045, 1.59, 0.24],
        [side * 0.17 + 0.045, 1.71, 0.24],
        [side * 0.17 - 0.045, 1.71, 0.24],
      ],
      paint.charcoal,
    );
  }
  return mesh;
}

function combine(...meshes) {
  const result = new Mesh();
  for (const mesh of meshes) {
    const offset = result.positions.length / 3;
    result.positions.push(...mesh.positions);
    result.uv.push(...mesh.uv);
    result.indices.push(...mesh.indices.map((index) => index + offset));
  }
  return result;
}

function kartNodes() {
  return [
    { name: "body", mesh: 0, children: [1, 3, 4, 5, 6] },
    { name: "driver", mesh: 1, children: [2] },
    { name: "cape", mesh: 2, translation: [0, 1.34, -0.43] },
    { name: "wheel_front_left", mesh: 3, translation: [-0.89, 0.39, 0.72] },
    { name: "wheel_front_right", mesh: 3, translation: [0.89, 0.39, 0.72] },
    { name: "wheel_rear_left", mesh: 3, translation: [-0.94, 0.39, -0.76] },
    { name: "wheel_rear_right", mesh: 3, translation: [0.94, 0.39, -0.76] },
  ];
}

function kartLODs() {
  const body = kartBody();
  const rider = driver();
  const cloth = cape();
  const lowWheel = wheel();
  const bodyExtra = bodyDetail();
  const driverExtra = driverDetail();
  const highWheel = wheel(16);
  const low = gltf([body, rider, cloth, lowWheel], kartNodes());
  const high = gltf(
    [combine(body, bodyExtra), combine(rider, driverExtra), cloth, highWheel],
    kartNodes(),
  );
  const lodNodes = kartNodes();
  // Detached extra nodes keep the seven animation nodes identical. The game
  // selects these meshes explicitly and supplies the corresponding body,
  // driver or wheel world transform. Drawing every node is not an LOD policy.
  lodNodes.push(
    { name: "body_detail", mesh: 4 },
    { name: "driver_detail", mesh: 5 },
    { name: "wheel_high", mesh: 6 },
  );
  const lod = gltf([body, rider, cloth, lowWheel, bodyExtra, driverExtra, highWheel], lodNodes);
  return { "kart-low": low, "kart-high": high, "kart-lod": lod };
}

function castle() {
  const mesh = new Mesh();
  mesh.box(0, 0, 0, 7, 5.5, 4.8, paint.stone);
  mesh.box(0, 5.5, 0, 3.3, 5.1, 3.3, paint.stone);
  mesh.spike([0, 10.6, 0], [0, 13.6, 0], 4.2, 4.2, paint.redShade);
  for (const side of [-1, 1]) {
    mesh.box(side * 3.9, 0, 0.6, 2.7, 7.1, 2.7, paint.stone);
    mesh.spike([side * 3.9, 7.1, 0.6], [side * 3.9, 10.2, 0.6], 3.5, 3.5, paint.redShade);
    for (const level of [3.1, 5.3]) {
      mesh.face(
        [
          [side * 3.9 - 0.26, level, 1.96],
          [side * 3.9 + 0.26, level, 1.96],
          [side * 3.9 + 0.26, level + 1, 1.96],
          [side * 3.9 - 0.26, level + 1, 1.96],
        ],
        paint.charcoal,
      );
    }
    mesh.box(side * 1.3, 5.5, 2, 0.8, 0.8, 0.8, paint.stone);
  }
  mesh.face(
    [
      [-0.8, 0, 2.42],
      [0.8, 0, 2.42],
      [0.8, 2.5, 2.42],
      [-0.8, 2.5, 2.42],
    ],
    paint.charcoal,
  );
  mesh.face(
    [
      [-0.8, 2.5, 2.42],
      [0.8, 2.5, 2.42],
      [0, 3.2, 2.42],
    ],
    paint.charcoal,
  );
  mesh.face(
    [
      [-0.25, 7.5, 1.67],
      [0.25, 7.5, 1.67],
      [0.25, 8.7, 1.67],
      [-0.25, 8.7, 1.67],
    ],
    paint.charcoal,
  );
  mesh.face(
    [
      [0, 13.4, 0],
      [0, 15.2, 0],
      [0.1, 15.2, 0],
      [0.1, 13.4, 0],
    ],
    paint.charcoal,
  );
  mesh.face(
    [
      [0.1, 15.1, 0],
      [1.6, 14.65, 0],
      [0.1, 14.25, 0],
    ],
    paint.red,
  );
  return mesh;
}

function roadside() {
  const mesh = new Mesh();
  mesh.crown(0, 0, 0, 1.45, 0.95, 1.25, paint.stone, 5);
  for (const [x, z] of [
    [-0.8, 0.3],
    [0.7, -0.2],
    [0.3, 0.7],
  ]) {
    mesh.face(
      [
        [x - 0.15, 0, z],
        [x, 0.7, z],
        [x + 0.1, 0, z],
      ],
      paint.leafShade,
    );
    mesh.face(
      [
        [x, 0, z - 0.15],
        [x, 0.55, z],
        [x, 0, z + 0.18],
      ],
      paint.leaf,
    );
    mesh.face(
      [
        [x - 0.15, 0.5, z],
        [x, 0.7, z],
        [x + 0.15, 0.5, z],
        [x, 0.35, z],
      ],
      paint.gold,
    );
  }
  return mesh;
}

function gltf(meshes, nodes) {
  const bufferViews = [];
  const accessors = [];
  const buffers = [];
  let byteLength = 0;
  function stream(values, width, componentType, type) {
    const alignment = (4 - (byteLength % 4)) % 4;
    if (alignment) {
      buffers.push(Buffer.alloc(alignment));
      byteLength += alignment;
    }
    const bytes = Buffer.alloc(values.length * width);
    values.forEach((value, index) => {
      if (componentType === 5126) {
        bytes.writeFloatLE(value, index * width);
      } else {
        bytes.writeUInt16LE(value, index * width);
      }
    });
    const view = bufferViews.length;
    bufferViews.push({ buffer: 0, byteOffset: byteLength, byteLength: bytes.length });
    buffers.push(bytes);
    byteLength += bytes.length;
    const components = type === "VEC3" ? 3 : type === "VEC2" ? 2 : 1;
    const accessor = { bufferView: view, componentType, count: values.length / components, type };
    if (type === "VEC3") {
      accessor.min = Array.from({ length: 3 }, (_, axis) =>
        Math.min(...values.filter((_, index) => index % 3 === axis)),
      );
      accessor.max = Array.from({ length: 3 }, (_, axis) =>
        Math.max(...values.filter((_, index) => index % 3 === axis)),
      );
    }
    accessors.push(accessor);
    return accessors.length - 1;
  }
  const geometry = meshes.map((mesh) => ({
    primitives: [
      {
        attributes: {
          POSITION: stream(mesh.positions, 4, 5126, "VEC3"),
          TEXCOORD_0: stream(mesh.uv, 4, 5126, "VEC2"),
        },
        indices: stream(mesh.indices, 2, 5123, "SCALAR"),
        material: 0,
      },
    ],
  }));
  const children = new Set(nodes.flatMap((node) => node.children ?? []));
  return {
    asset: { version: "2.0", generator: "Sunline Sprint original asset workshop" },
    scene: 0,
    scenes: [{ nodes: nodes.map((_, index) => index).filter((index) => !children.has(index)) }],
    nodes: nodes.map((node) => ({
      ...node,
      ...(node.translation
        ? {
            translation: [node.translation[0], node.translation[1], -node.translation[2]].map(snap),
          }
        : {}),
    })),
    meshes: geometry,
    accessors,
    bufferViews,
    buffers: [
      {
        byteLength,
        uri: `data:application/octet-stream;base64,${Buffer.concat(buffers).toString("base64")}`,
      },
    ],
    images: [{ uri: "atlas.png" }],
    samplers: [{ magFilter: 9728, minFilter: 9728, wrapS: 33071, wrapT: 33071 }],
    textures: [{ sampler: 0, source: 0 }],
    materials: [
      {
        name: "sunline_painted_atlas",
        pbrMetallicRoughness: {
          baseColorTexture: { index: 0 },
          metallicFactor: 0,
          roughnessFactor: 1,
        },
        alphaMode: "OPAQUE",
      },
    ],
  };
}

export async function generateAssets() {
  await mkdir(assetDirectory, { recursive: true });
  await writeFile(resolve(assetDirectory, "atlas.png"), atlas());
  const models = {
    ...kartLODs(),
    tree: gltf([tree()], [{ name: "tree", mesh: 0 }]),
    castle: gltf([castle()], [{ name: "castle", mesh: 0 }]),
    roadside: gltf([roadside()], [{ name: "roadside", mesh: 0 }]),
  };
  for (const [name, model] of Object.entries(models)) {
    await writeFile(resolve(assetDirectory, `${name}.gltf`), JSON.stringify(model, null, 2) + "\n");
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  await generateAssets();
}

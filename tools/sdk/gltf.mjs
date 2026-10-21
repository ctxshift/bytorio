import { readFile, realpath, stat } from "node:fs/promises";
import { dirname, resolve, sep } from "node:path";
import { inflateSync } from "node:zlib";
import { chunks } from "./cartridge.mjs";
import {
  COLOR_OPAQUE_BLACK,
  PROFILE_ALPHA_3D,
  PROFILE_TEXTURED_3D,
} from "../../runtime/odin/web/constants.js";

const schema = JSON.parse(
  await readFile(new URL("../../sdk/resource-protocol.json", import.meta.url)),
);
const limits = schema;
const contract = JSON.parse(await readFile(new URL("../../sdk/contract.json", import.meta.url)));
export const IMPORT_LIMITS = Object.freeze({
  inputBytes: 8 * 1024 * 1024,
  nodes: 128,
  primitives: 128,
  draws: 256,
  materials: 64,
  sourceBytes: 128 * 1024,
  uploadBytes: limits.maxPayload / 2,
});
const COMPONENT = Object.freeze({ u8: 5121, u16: 5123, u32: 5125, f32: 5126 });
const UNSIGNED_BYTE_MAX = 2 ** 8 - 1;
const UNSIGNED_SHORT_MAX = 2 ** 16 - 1;
const UNSIGNED_INT_MAX = 2 ** 32 - 1;
const COMPONENTS = new Map([
  [COMPONENT.u8, [1, "getUint8", UNSIGNED_BYTE_MAX]],
  [COMPONENT.u16, [2, "getUint16", UNSIGNED_SHORT_MAX]],
  [COMPONENT.u32, [4, "getUint32", UNSIGNED_INT_MAX]],
  [COMPONENT.f32, [4, "getFloat32", 1]],
]);
const TYPES = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4 };
const IDENTITY = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
const GLB_MAGIC = 0x46546c67;
const GLB_JSON = 0x4e4f534a;
const GLB_BIN = 0x004e4942;
const PNG_RGB = 2,
  PNG_RGBA = 6;
const WRAP_REPEAT = 10497,
  WRAP_CLAMP = 33071,
  FILTER_NEAREST = 9728;

function check(condition, message) {
  if (!condition) {
    throw new Error(`glTF import: ${message}`);
  }
}
function integer(value, maximum, label) {
  check(Number.isSafeInteger(value) && value >= 0 && value <= maximum, `invalid ${label}`);
  return value;
}
function reference(array, index, label) {
  integer(index, (array?.length ?? 0) - 1, label);
  return array[index];
}
function finite(value, bound, label) {
  check(Number.isFinite(value) && Math.abs(value) <= bound, `invalid ${label}`);
  return value;
}
function vector(value, length, fallback, label) {
  value ??= fallback;
  check(Array.isArray(value) && value.length === length, `invalid ${label}`);
  return value.map((x) => finite(x, limits.max3dCoordinate, label));
}
function noExtensions(value, depth = 0) {
  check(depth <= IMPORT_LIMITS.nodes, "JSON nesting is too deep");
  if (!value || typeof value !== "object") {
    return;
  }
  check(
    !value.extensions || Object.keys(value.extensions).length === 0,
    "extensions are unsupported",
  );
  for (const [key, child] of Object.entries(value)) {
    if (key !== "extras") {
      noExtensions(child, depth + 1);
    }
  }
}
export function multiply(a, b) {
  const result = Array(16).fill(0);
  for (let column = 0; column < 4; column++) {
    for (let row = 0; row < 4; row++) {
      for (let k = 0; k < 4; k++) {
        result[column * 4 + row] += a[k * 4 + row] * b[column * 4 + k];
      }
      result[column * 4 + row] = Math.fround(result[column * 4 + row]);
    }
  }
  return result;
}
function transform(node) {
  let m;
  if (node.matrix !== undefined) {
    check(
      node.translation === undefined && node.rotation === undefined && node.scale === undefined,
      "node cannot mix matrix and TRS",
    );
    m = vector(node.matrix, 16, null, "node matrix");
  } else {
    const t = vector(node.translation, 3, [0, 0, 0], "translation");
    const s = vector(node.scale, 3, [1, 1, 1], "scale");
    const [x, y, z, w] = vector(node.rotation, 4, [0, 0, 0, 1], "rotation");
    check(
      Math.abs(x * x + y * y + z * z + w * w - 1) < 0.0001,
      "rotation quaternion must be unit length",
    );
    m = [
      (1 - 2 * y * y - 2 * z * z) * s[0],
      (2 * x * y + 2 * z * w) * s[0],
      (2 * x * z - 2 * y * w) * s[0],
      0,
      (2 * x * y - 2 * z * w) * s[1],
      (1 - 2 * x * x - 2 * z * z) * s[1],
      (2 * y * z + 2 * x * w) * s[1],
      0,
      (2 * x * z + 2 * y * w) * s[2],
      (2 * y * z - 2 * x * w) * s[2],
      (1 - 2 * x * x - 2 * y * y) * s[2],
      0,
      ...t,
      1,
    ];
  }
  check(m[3] === 0 && m[7] === 0 && m[11] === 0 && m[15] === 1, "node matrix must be affine");
  const determinant =
    m[0] * (m[5] * m[10] - m[9] * m[6]) -
    m[4] * (m[1] * m[10] - m[9] * m[2]) +
    m[8] * (m[1] * m[6] - m[5] * m[2]);
  check(Math.abs(determinant) > 1e-12, "singular node transform");
  // Reflect Z on both sides: C * M * C. Local positions reflect Z separately.
  return m.map((value, i) =>
    Math.fround(value * ((i % 4 === 2) !== (Math.floor(i / 4) === 2) ? -1 : 1)),
  );
}
function paeth(a, b, c) {
  const p = a + b - c,
    da = Math.abs(p - a),
    db = Math.abs(p - b),
    dc = Math.abs(p - c);
  return da <= db && da <= dc ? a : db <= dc ? b : c;
}
export function decodeTexture(bytes) {
  const parts = chunks(bytes);
  check(parts[0].type === "IHDR" && parts[0].data.length === 13, "invalid PNG header");
  const h = parts[0].data,
    width = h.readUInt32BE(0),
    height = h.readUInt32BE(4);
  check(
    width > 0 &&
      width <= limits.maxImageAxis &&
      height > 0 &&
      height <= limits.maxImageAxis &&
      width * height * 4 <= IMPORT_LIMITS.uploadBytes,
    "PNG dimensions exceed import budget",
  );
  check(
    h[8] === 8 && [PNG_RGB, PNG_RGBA].includes(h[9]) && h[10] === 0 && h[11] === 0 && h[12] === 0,
    "only noninterlaced 8-bit RGB/RGBA PNG textures are supported",
  );
  const idat = [];
  let ended = false;
  for (const part of parts.slice(1, -1)) {
    if (part.type === "IDAT") {
      check(!ended, "PNG IDAT chunks must be consecutive");
      idat.push(part.data);
    } else {
      if (idat.length) {
        ended = true;
      }
      check(part.type !== "tRNS", "PNG tRNS transparency is unsupported; export RGBA8");
      check(!["acTL", "fcTL", "fdAT"].includes(part.type), "animated PNG textures are unsupported");
      check(part.type[0] === part.type[0].toLowerCase(), `unsupported PNG chunk ${part.type}`);
    }
  }
  check(idat.length > 0, "PNG has no image data");
  const channels = h[9] === PNG_RGBA ? 4 : 3,
    stride = width * channels;
  const size = (stride + 1) * height;
  const compressed = Buffer.concat(idat);
  const decodedStream = inflateSync(compressed, { maxOutputLength: size, info: true });
  check(
    decodedStream.engine.bytesWritten === compressed.length,
    "PNG compressed stream has trailing bytes",
  );
  const raw = decodedStream.buffer;
  check(raw.length === size, "PNG decoded size mismatch");
  const decoded = Buffer.alloc(stride * height),
    pixels = [];
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    check(filter <= 4, "invalid PNG filter");
    for (let x = 0; x < stride; x++) {
      const at = y * stride + x,
        left = x >= channels ? decoded[at - channels] : 0;
      const above = y > 0 ? decoded[at - stride] : 0;
      const diagonal = x >= channels && y > 0 ? decoded[at - stride - channels] : 0;
      const prediction = [
        0,
        left,
        above,
        Math.floor((left + above) / 2),
        paeth(left, above, diagonal),
      ][filter];
      decoded[at] = (raw[y * (stride + 1) + x + 1] + prediction) & 255;
    }
    for (let x = 0; x < width; x++) {
      const at = y * stride + x * channels;
      pixels.push(
        decoded[at],
        decoded[at + 1],
        decoded[at + 2],
        channels === 4 ? decoded[at + 3] : 255,
      );
    }
  }
  return { width, height, pixels };
}
function srgbToLinear(value) {
  return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
}
function linearToSrgb(value) {
  return value <= 0.0031308 ? value * 12.92 : 1.055 * value ** (1 / 2.4) - 0.055;
}

export async function readGltf(path) {
  const input = await realpath(path),
    root = dirname(input);
  let inputBytes = 0;
  async function read(path) {
    const size = (await stat(path)).size;
    check(size <= IMPORT_LIMITS.inputBytes - inputBytes, "input byte budget exceeded");
    inputBytes += size;
    const bytes = await readFile(path);
    check(bytes.length === size, "input changed while reading");
    return bytes;
  }
  async function uri(value, kind) {
    check(typeof value === "string", `missing ${kind} URI`);
    if (value.startsWith("data:")) {
      const match = value.match(
        /^data:(application\/(?:octet-stream|gltf-buffer)|image\/png);base64,([A-Za-z0-9+/]*={0,2})$/,
      );
      check(
        match &&
          match[2].length % 4 === 0 &&
          (kind === "image" ? match[1] === "image/png" : match[1] !== "image/png"),
        "unsupported data URI",
      );
      check(
        match[2].length <= Math.ceil((IMPORT_LIMITS.inputBytes - inputBytes) / 3) * 4,
        "data URI byte budget exceeded",
      );
      const bytes = Buffer.from(match[2], "base64");
      check(bytes.toString("base64") === match[2], "noncanonical base64 data URI");
      inputBytes += bytes.length;
      check(inputBytes <= IMPORT_LIMITS.inputBytes, "input byte budget exceeded");
      return bytes;
    }
    value = decodeURIComponent(value);
    check(
      value.length > 0 && !value.startsWith("/") && !/[\\:\0?#]/.test(value),
      "external URI must be a relative local path",
    );
    const file = await realpath(resolve(root, value));
    check(file.startsWith(root + sep), "external URI escapes the asset directory");
    return read(file);
  }
  const file = await read(input);
  let json = file,
    binary;
  if (file.length >= 4 && file.readUInt32LE(0) === GLB_MAGIC) {
    check(
      file.length >= 20 && file.readUInt32LE(4) === 2 && file.readUInt32LE(8) === file.length,
      "invalid GLB header",
    );
    let offset = 12,
      index = 0;
    while (offset < file.length) {
      check(offset + 8 <= file.length, "truncated GLB chunk");
      const length = file.readUInt32LE(offset),
        type = file.readUInt32LE(offset + 4);
      check(length % 4 === 0 && offset + 8 + length <= file.length, "invalid GLB chunk length");
      const data = file.subarray(offset + 8, offset + 8 + length);
      if (index === 0) {
        check(type === GLB_JSON, "GLB JSON must be first");
        json = data;
      } else {
        check(index === 1 && type === GLB_BIN, "unsupported GLB chunk");
        binary = data;
      }
      offset += 8 + length;
      index++;
    }
  }
  const source = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(json));
  check(
    source !== null && typeof source === "object" && !Array.isArray(source),
    "root must be an object",
  );
  check(
    source.asset?.version === "2.0" &&
      (!source.asset.minVersion || source.asset.minVersion === "2.0"),
    "requires glTF 2.0",
  );
  check(
    !source.extensionsUsed?.length && !source.extensionsRequired?.length,
    "extensions are unsupported",
  );
  noExtensions(source);
  check(
    !source.skins?.length && !source.animations?.length && !source.cameras?.length,
    "skins, animations and cameras are unsupported; animate rigid nodes in game code",
  );
  for (const name of [
    "buffers",
    "bufferViews",
    "accessors",
    "meshes",
    "nodes",
    "scenes",
    "materials",
    "textures",
    "images",
    "samplers",
    "skins",
    "animations",
    "cameras",
  ]) {
    check(source[name] === undefined || Array.isArray(source[name]), `invalid ${name} array`);
    check(
      (source[name] ?? []).every(
        (value) => value !== null && typeof value === "object" && !Array.isArray(value),
      ),
      `invalid ${name} entry`,
    );
  }
  check(
    source.nodes?.length > 0 && source.nodes.length <= IMPORT_LIMITS.nodes,
    "node budget exceeded or empty scene",
  );
  const buffers = [];
  for (const [i, buffer] of (source.buffers ?? []).entries()) {
    const length = integer(buffer.byteLength, IMPORT_LIMITS.inputBytes, "buffer byteLength");
    const bytes = buffer.uri === undefined ? binary : await uri(buffer.uri, "buffer");
    check(
      bytes &&
        (buffer.uri !== undefined || i === 0) &&
        bytes.length >= length &&
        bytes.length <= length + (buffer.uri === undefined ? 3 : 0),
      "buffer length mismatch",
    );
    buffers.push(bytes.subarray(0, length));
  }
  function view(index) {
    const v = reference(source.bufferViews, index, "buffer view"),
      b = reference(buffers, v.buffer, "buffer");
    const start = integer(v.byteOffset ?? 0, b.length, "buffer view offset");
    const length = integer(v.byteLength, b.length - start, "buffer view length");
    return { ...v, bytes: b.subarray(start, start + length), start };
  }
  function accessor(index, semantic) {
    const a = reference(source.accessors, index, "accessor");
    check(!a.sparse, "sparse accessors are unsupported");
    const component = COMPONENTS.get(a.componentType),
      width = TYPES[a.type];
    check(component && width, "unsupported accessor component/type");
    check(
      a.normalized === undefined || typeof a.normalized === "boolean",
      "invalid normalized flag",
    );
    const [bytes, getter, divisor] = component,
      v = view(a.bufferView);
    const count = integer(
      a.count,
      semantic === "indices" ? limits.maxMeshIndices : limits.maxMeshVertices,
      "accessor count",
    );
    check(count > 0, "empty accessor");
    const size = width * bytes,
      start = integer(a.byteOffset ?? 0, v.bytes.length, "accessor offset");
    const stride = integer(v.byteStride ?? size, 252, "accessor stride");
    check(
      stride >= size &&
        (semantic === "indices" || (start % 4 === 0 && stride % 4 === 0)) &&
        (v.byteStride === undefined || stride % 4 === 0) &&
        (v.start + start) % bytes === 0 &&
        start % bytes === 0 &&
        start + (count - 1) * stride + size <= v.bytes.length,
      "accessor range, stride or alignment is invalid",
    );
    if (semantic === "indices") {
      check(
        a.type === "SCALAR" &&
          a.componentType !== COMPONENT.f32 &&
          !a.normalized &&
          v.byteStride === undefined,
        "invalid index accessor",
      );
    } else if (semantic === "POSITION" || semantic === "NORMAL") {
      check(
        a.type === "VEC3" && a.componentType === COMPONENT.f32 && !a.normalized,
        `invalid ${semantic} accessor`,
      );
    } else {
      check(
        (semantic === "TEXCOORD_0" ? a.type === "VEC2" : ["VEC3", "VEC4"].includes(a.type)) &&
          (a.componentType === COMPONENT.f32
            ? !a.normalized
            : [COMPONENT.u8, COMPONENT.u16].includes(a.componentType) && a.normalized),
        `invalid ${semantic} accessor`,
      );
    }
    const data = new DataView(v.bytes.buffer, v.bytes.byteOffset, v.bytes.length),
      result = [];
    for (let i = 0; i < count; i++) {
      const row = [];
      for (let k = 0; k < width; k++) {
        const value = data[getter](start + i * stride + k * bytes, true);
        check(
          semantic !== "indices" || value !== divisor,
          "primitive-restart indices are unsupported",
        );
        row.push(
          finite(
            value / (a.normalized ? divisor : 1),
            semantic === "indices"
              ? limits.maxMeshVertices
              : semantic === "TEXCOORD_0"
                ? limits.maxTextureCoordinate
                : limits.max3dCoordinate,
            semantic,
          ),
        );
      }
      result.push(row);
    }
    return result;
  }
  const materials = [],
    materialIds = new Map(),
    imageCache = new Map();
  let uploadBytes = 0;
  async function material(index) {
    const key = index ?? -1;
    if (materialIds.has(key)) {
      return materialIds.get(key);
    }
    check(materials.length < IMPORT_LIMITS.materials, "material budget exceeded");
    const m = index === undefined ? {} : reference(source.materials, index, "material");
    const pbr = m.pbrMetallicRoughness ?? {};
    const emissive = vector(m.emissiveFactor, 3, [0, 0, 0], "emissive factor");
    check(
      !m.normalTexture &&
        !m.occlusionTexture &&
        !pbr.metallicRoughnessTexture &&
        emissive.every((x) => x === 0) &&
        !m.emissiveTexture,
      "normal, occlusion, emissive and metallic/roughness maps are unsupported",
    );
    const alpha = m.alphaMode ?? "OPAQUE";
    check(alpha === "OPAQUE" || alpha === "MASK", "only OPAQUE and MASK materials are supported");
    const factor = vector(pbr.baseColorFactor, 4, [1, 1, 1, 1], "base color factor");
    check(
      factor.every((x) => x >= 0 && x <= 1),
      "base color factor must be in [0,1]",
    );
    let image = { width: 1, height: 1, pixels: [255, 255, 255, 255] },
      addressU = "clamp",
      addressV = "clamp";
    if (pbr.baseColorTexture !== undefined) {
      check((pbr.baseColorTexture.texCoord ?? 0) === 0, "only TEXCOORD_0 is supported");
      const texture = reference(source.textures, pbr.baseColorTexture.index, "texture");
      const sampler =
        texture.sampler === undefined ? {} : reference(source.samplers, texture.sampler, "sampler");
      check(
        [undefined, FILTER_NEAREST].includes(sampler.magFilter) &&
          [undefined, FILTER_NEAREST].includes(sampler.minFilter),
        "only nearest texture filtering without mipmaps is supported",
      );
      function address(value) {
        check([WRAP_CLAMP, WRAP_REPEAT].includes(value), "unsupported texture wrap mode");
        return value === WRAP_REPEAT ? "repeat" : "clamp";
      }
      addressU = address(sampler.wrapS ?? WRAP_REPEAT);
      addressV = address(sampler.wrapT ?? WRAP_REPEAT);
      if (!imageCache.has(texture.source)) {
        const img = reference(source.images, texture.source, "image");
        check(
          img.mimeType === undefined || img.mimeType === "image/png",
          "only PNG images are supported",
        );
        check(
          (img.uri !== undefined) !== (img.bufferView !== undefined),
          "image requires exactly one URI or bufferView",
        );
        imageCache.set(
          texture.source,
          decodeTexture(
            img.uri === undefined ? view(img.bufferView).bytes : await uri(img.uri, "image"),
          ),
        );
      }
      image = imageCache.get(texture.source);
    }
    const pixels = image.pixels.map((value, i) => {
      const channel = i % 4,
        sourceAlpha = image.pixels[i - channel + 3];
      const opacity = alpha === "OPAQUE" ? 1 : (sourceAlpha / 255) * factor[3];
      return Math.round(
        255 *
          (channel === 3
            ? opacity
            : linearToSrgb(srgbToLinear(value / 255) * factor[channel]) * opacity),
      );
    });
    const cutoff = finite(m.alphaCutoff ?? 0.5, 1, "alpha cutoff");
    check(cutoff >= 0, "alpha cutoff must be in [0,1]");
    const result = {
      ...image,
      pixels,
      addressU,
      addressV,
      cutoff: alpha === "MASK" ? Math.ceil(cutoff * 255) : null,
    };
    uploadBytes += pixels.length + limits.descriptorBytes;
    check(uploadBytes <= IMPORT_LIMITS.uploadBytes, "upload byte budget exceeded");
    const id = materials.length;
    materialIds.set(key, id);
    materials.push(result);
    return id;
  }
  const primitives = [],
    meshIds = new Map();
  async function mesh(index) {
    if (meshIds.has(index)) {
      return meshIds.get(index);
    }
    const m = reference(source.meshes, index, "mesh");
    check(
      !m.weights && Array.isArray(m.primitives) && m.primitives.length > 0,
      "invalid mesh or unsupported morph weights",
    );
    const ids = [];
    for (const p of m.primitives) {
      check(primitives.length < IMPORT_LIMITS.primitives, "primitive budget exceeded");
      check((p.mode ?? 4) === 4 && !p.targets, "only static TRIANGLES primitives are supported");
      check(
        p.attributes &&
          Object.keys(p.attributes).every((x) =>
            ["POSITION", "NORMAL", "TEXCOORD_0", "COLOR_0"].includes(x),
          ),
        "unsupported vertex attribute",
      );
      const positions = accessor(p.attributes.POSITION, "POSITION");
      const uv =
        p.attributes.TEXCOORD_0 === undefined
          ? null
          : accessor(p.attributes.TEXCOORD_0, "TEXCOORD_0");
      const colors =
        p.attributes.COLOR_0 === undefined ? null : accessor(p.attributes.COLOR_0, "COLOR_0");
      for (const values of [
        uv,
        colors,
        p.attributes.NORMAL === undefined ? null : accessor(p.attributes.NORMAL, "NORMAL"),
      ]) {
        check(values === null || values.length === positions.length, "attribute count mismatch");
      }
      const materialId = await material(p.material);
      if (
        p.material !== undefined &&
        source.materials[p.material]?.pbrMetallicRoughness?.baseColorTexture
      ) {
        check(uv, "textured primitive requires TEXCOORD_0");
      }
      const indices = accessor(p.indices, "indices").flat();
      check(
        indices.length % 3 === 0 && indices.every((x) => x < positions.length),
        "triangle indices exceed vertices or are incomplete",
      );
      for (let i = 0; i < indices.length; i += 3) {
        [indices[i + 1], indices[i + 2]] = [indices[i + 2], indices[i + 1]];
      }
      const vertices = positions.map(([x, y, z], i) => {
        const color = colors?.[i] ?? [1, 1, 1];
        check(
          color.every((v) => v >= 0 && v <= 1) && (color.length === 3 || color[3] === 1),
          "vertex colors must be in [0,1] with opaque alpha",
        );
        const packed =
          (Math.round(color[0] * 255) |
            (Math.round(color[1] * 255) << 8) |
            (Math.round(color[2] * 255) << 16) |
            COLOR_OPAQUE_BLACK) >>>
          0;
        return { position: [x, y, -z].map(Math.fround), uv: uv?.[i] ?? [0, 0], color: packed };
      });
      uploadBytes +=
        vertices.length * limits.texturedVertexBytes + indices.length * limits.meshIndexBytes;
      check(uploadBytes <= IMPORT_LIMITS.uploadBytes, "upload byte budget exceeded");
      ids.push(primitives.length);
      primitives.push({ vertices, indices, material: materialId });
    }
    meshIds.set(index, ids);
    return ids;
  }
  const scene = reference(source.scenes, source.scene ?? 0, "scene");
  check(Array.isArray(scene.nodes) && scene.nodes.length > 0, "selected scene is empty");
  const nodes = [],
    seen = new Set(),
    names = new Set();
  let draws = 0;
  async function node(index, parent, parentWorld) {
    check(!seen.has(index), "node cycle, repeated root or multiple parents");
    seen.add(index);
    const n = reference(source.nodes, index, "node");
    check(
      n.skin === undefined && n.camera === undefined && n.weights === undefined,
      "skinned/camera/morph nodes are unsupported",
    );
    const name = n.name ?? `node_${index}`;
    check(
      typeof name === "string" &&
        name.length > 0 &&
        Buffer.byteLength(name) <= 64 &&
        [...name].every(
          (character) => character.codePointAt(0) >= 32 && character.codePointAt(0) !== 127,
        ) &&
        !names.has(name),
      "node names must be unique nonempty strings, at most 64 bytes",
    );
    names.add(name);
    const local = transform(n),
      world = multiply(parentWorld, local);
    check(
      world.every((x) => Number.isFinite(x) && Math.abs(x) <= limits.max3dCoordinate),
      "world transform exceeds coordinate bounds",
    );
    const geometry = n.mesh === undefined ? [] : await mesh(n.mesh);
    draws += geometry.length;
    check(draws <= IMPORT_LIMITS.draws, "instance draw budget exceeded");
    for (const id of geometry) {
      for (const v of primitives[id].vertices) {
        for (let axis = 0; axis < 3; axis++) {
          finite(
            world[axis] * v.position[0] +
              world[4 + axis] * v.position[1] +
              world[8 + axis] * v.position[2] +
              world[12 + axis],
            limits.max3dCoordinate,
            "world position",
          );
        }
      }
    }
    const id = nodes.length;
    nodes.push({ name, parent, local, world, primitives: geometry });
    check(n.children === undefined || Array.isArray(n.children), "invalid children array");
    for (const child of n.children ?? []) {
      await node(child, id, world);
    }
  }
  for (const root of scene.nodes) {
    await node(root, -1, IDENTITY);
  }
  check(primitives.length > 0, "scene contains no geometry");
  const profile = contract.profiles.find(
    (item) =>
      item.id ===
      (materials.some((m) => m.cutoff !== null) ? PROFILE_ALPHA_3D : PROFILE_TEXTURED_3D),
  );
  return {
    format: "bytorio-model",
    version: 1,
    minimumSdk: profile.sdk,
    sdkVersionWord: profile.sdkWord,
    profile: profile.name,
    nodes,
    primitives,
    materials,
    report: {
      inputBytes,
      uploadBytes,
      vertices: primitives.reduce((n, p) => n + p.vertices.length, 0),
      triangles: primitives.reduce((n, p) => n + p.indices.length / 3, 0),
      draws,
      shading:
        "Base color only; nearest textures, two-sided triangles and flat runtime normals. Linear vertex weights use runtime byte tints; alpha is RGBA8-quantized after factor baking. PBR lighting and smooth normals are not reproduced.",
    },
  };
}

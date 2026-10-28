import { open, mkdir, lstat, link, rename, rm } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { randomUUID } from "node:crypto";
import { deflateSync, inflateSync } from "node:zlib";
import { chunk, chunks, signature } from "../sdk/cartridge.mjs";
import contract from "../../sdk/contract.json" with { type: "json" };
import { metadataMask, moldMask } from "./cover-lettering.mjs";

// Layout v1, in output pixels. The shell is the website's unmodified brand asset.
export const coverLayout = Object.freeze({
  width: 839,
  height: 1024,
  stickerX: 148,
  stickerY: 158,
  stickerSize: 554,
  brandY: 717,
  brandWidth: 170,
  detailY: 119,
});
const maxInputBytes = 32 * 1024 * 1024;
const maxInputAxis = 4096;
const displays = contract.displayModes.map((mode) => mode.join("x"));

function requireValue(condition, message) {
  if (!condition) {
    throw new Error(`Cartridge cover: ${message}`);
  }
}

export function coverOptions(args) {
  const options = {
    input: "",
    output: "",
    language: "luau",
    display: contract.defaultDisplayMode.join("x"),
    force: false,
  };
  const seen = new Set();
  for (let index = 0; index < args.length; index++) {
    const arg = args[index];
    if (!arg.startsWith("--")) {
      requireValue(!options.input, "expected one square sticker PNG");
      options.input = arg;
      continue;
    }
    requireValue(!seen.has(arg), `duplicate option ${arg}`);
    seen.add(arg);
    if (arg === "--force") {
      options.force = true;
    } else {
      requireValue(["--output", "--language", "--display"].includes(arg), `unknown option ${arg}`);
      const value = args[++index];
      requireValue(value && !value.startsWith("--"), `expected a value for ${arg}`);
      options[arg.slice(2)] = value;
    }
  }
  requireValue(options.input && options.output, "expected <sticker.png> --output <cover.png>");
  requireValue(/\.png$/i.test(options.output), "output must end in .png");
  requireValue(["luau", "odin"].includes(options.language), "language must be luau or odin");
  requireValue(displays.includes(options.display), "display must be 640x360 or 320x180");
  return options;
}

function paeth(a, b, c) {
  const p = a + b - c;
  const da = Math.abs(p - a),
    db = Math.abs(p - b),
    dc = Math.abs(p - c);
  return da <= db && da <= dc ? a : db <= dc ? b : c;
}

// A deliberately bounded decoder: no OS codecs, fonts, network or native addons.
export function decodeCoverPng(bytes) {
  requireValue(bytes.length <= maxInputBytes, "PNG exceeds 32 MiB");
  const parts = chunks(bytes);
  requireValue(parts[0].type === "IHDR" && parts[0].data.length === 13, "invalid PNG header");
  const header = parts[0].data;
  const width = header.readUInt32BE(0),
    height = header.readUInt32BE(4);
  requireValue(
    width > 0 && height > 0 && width <= maxInputAxis && height <= maxInputAxis,
    "PNG dimensions must be 1..4096",
  );
  requireValue(
    header[8] === 8 &&
      [2, 6].includes(header[9]) &&
      header[10] === 0 &&
      header[11] === 0 &&
      header[12] === 0,
    "export a noninterlaced 8-bit RGB or RGBA PNG",
  );
  const data = [];
  let ended = false;
  for (const part of parts.slice(1, -1)) {
    requireValue(
      !["caRt", "coNt", "saVe"].includes(part.type),
      "use artwork, not a packed cartridge",
    );
    requireValue(
      !["acTL", "fcTL", "fdAT", "tRNS"].includes(part.type),
      "animation and tRNS are unsupported; export RGBA PNG",
    );
    if (part.type === "IDAT") {
      requireValue(!ended, "PNG IDAT chunks must be consecutive");
      data.push(part.data);
    } else {
      if (data.length) {
        ended = true;
      }
      requireValue(
        part.type === "PLTE" || /^[a-z]/.test(part.type),
        `unsupported PNG chunk ${part.type}`,
      );
      if (part.type === "PLTE") {
        requireValue(
          !data.length &&
            part.data.length > 0 &&
            part.data.length <= 768 &&
            part.data.length % 3 === 0,
          "invalid PNG palette",
        );
      }
    }
  }
  requireValue(data.length > 0, "PNG has no image data");
  const channels = header[9] === 6 ? 4 : 3;
  const stride = width * channels;
  const expected = (stride + 1) * height;
  const compressed = Buffer.concat(data);
  const stream = inflateSync(compressed, { maxOutputLength: expected, info: true });
  requireValue(
    stream.buffer.length === expected && stream.engine.bytesWritten === compressed.length,
    "PNG decoded size or compressed stream mismatch",
  );
  const decoded = Buffer.alloc(stride * height);
  const pixels = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y++) {
    const filter = stream.buffer[y * (stride + 1)];
    requireValue(filter <= 4, "invalid PNG filter");
    for (let x = 0; x < stride; x++) {
      const at = y * stride + x;
      const left = x >= channels ? decoded[at - channels] : 0;
      const above = y ? decoded[at - stride] : 0;
      const diagonal = y && x >= channels ? decoded[at - stride - channels] : 0;
      const prediction =
        filter === 0
          ? 0
          : filter === 1
            ? left
            : filter === 2
              ? above
              : filter === 3
                ? Math.floor((left + above) / 2)
                : paeth(left, above, diagonal);
      decoded[at] = (stream.buffer[y * (stride + 1) + x + 1] + prediction) & 255;
    }
    for (let x = 0; x < width; x++) {
      const source = y * stride + x * channels;
      const destination = (y * width + x) * 4;
      pixels[destination] = decoded[source];
      pixels[destination + 1] = decoded[source + 1];
      pixels[destination + 2] = decoded[source + 2];
      pixels[destination + 3] = channels === 4 ? decoded[source + 3] : 255;
    }
  }
  return { width, height, pixels };
}

export function encodeCoverPng({ width, height, pixels }) {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 6;
  const rows = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; y++) {
    pixels.copy(rows, y * (width * 4 + 1) + 1, y * width * 4, (y + 1) * width * 4);
  }
  return Buffer.concat([
    signature,
    chunk("IHDR", header),
    chunk("IDAT", deflateSync(rows, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

function blend(image, x, y, color) {
  const at = (y * image.width + x) * 4;
  const alpha = color[3] / 255;
  const remaining = (image.pixels[at + 3] / 255) * (1 - alpha);
  const total = alpha + remaining;
  for (let channel = 0; channel < 3; channel++) {
    image.pixels[at + channel] = total
      ? Math.round((color[channel] * alpha + image.pixels[at + channel] * remaining) / total)
      : 0;
  }
  image.pixels[at + 3] = Math.round(total * 255);
}

// Pixel-center bilinear sampling in premultiplied alpha prevents dark fringes.
function layer(destination, source, left, top, width, height) {
  for (let y = 0; y < height; y++) {
    const sy = Math.max(0, Math.min(source.height - 1, ((y + 0.5) * source.height) / height - 0.5));
    const y0 = Math.floor(sy),
      fy = sy - y0;
    for (let x = 0; x < width; x++) {
      const sx = Math.max(0, Math.min(source.width - 1, ((x + 0.5) * source.width) / width - 0.5));
      const x0 = Math.floor(sx),
        fx = sx - x0;
      const color = [0, 0, 0, 0];
      for (let dy = 0; dy < 2; dy++) {
        for (let dx = 0; dx < 2; dx++) {
          const at =
            (Math.min(y0 + dy, source.height - 1) * source.width +
              Math.min(x0 + dx, source.width - 1)) *
            4;
          const weight = (dx ? fx : 1 - fx) * (dy ? fy : 1 - fy);
          const alpha = source.pixels[at + 3] * weight;
          for (let channel = 0; channel < 3; channel++) {
            color[channel] += source.pixels[at + channel] * alpha;
          }
          color[3] += alpha;
        }
      }
      for (let channel = 0; channel < 3; channel++) {
        color[channel] = color[3] ? color[channel] / color[3] : 0;
      }
      blend(destination, left + x, top + y, color);
    }
  }
}

// Extract the real wordmark from the website's logo, excluding the fox at right.
// Explicit bounds make a brand-asset change a reviewable layout change.
export function extractWordmark(logo) {
  const source = decodeCoverPng(logo);
  requireValue(
    source.width === 2172 && source.height === 724,
    "brand logo changed; update the wordmark crop",
  );
  const width = 1645,
    height = 480,
    top = 120;
  const pixels = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y++) {
    source.pixels.copy(
      pixels,
      y * width * 4,
      (top + y) * source.width * 4,
      ((top + y) * source.width + width) * 4,
    );
  }
  // The red extrusion is a solid backing around the white letter faces. Using
  // its silhouette would fill counters and merge letters when made monochrome.
  // Extract the neutral, light face coverage before molding it into the shell.
  for (let at = 0; at < pixels.length; at += 4) {
    const neutral = Math.min(pixels[at], pixels[at + 1], pixels[at + 2]);
    const face = Math.max(0, Math.min(1, (neutral - 100) / 80));
    pixels[at + 3] = Math.round(pixels[at + 3] * face);
  }
  return { width, height, pixels };
}

export function composeCover(stickerBytes, { shell, logo }, options) {
  requireValue(["luau", "odin"].includes(options.language), "language must be luau or odin");
  requireValue(displays.includes(options.display), "unsupported display");
  const sticker = decodeCoverPng(stickerBytes);
  requireValue(sticker.width === sticker.height, "sticker must be square; no cropping is applied");
  const template = decodeCoverPng(shell);
  const layout = coverLayout;
  const image = {
    width: layout.width,
    height: layout.height,
    pixels: Buffer.alloc(layout.width * layout.height * 4),
  };
  layer(image, template, 0, 0, image.width, image.height);
  layer(image, sticker, layout.stickerX, layout.stickerY, layout.stickerSize, layout.stickerSize);
  const wordmark = extractWordmark(logo);
  const brandX = Math.floor((image.width - layout.brandWidth) / 2);
  const brandHeight = Math.round((layout.brandWidth * wordmark.height) / wordmark.width);
  const brandMask = {
    width: layout.brandWidth,
    height: brandHeight,
    pixels: Buffer.alloc(layout.brandWidth * brandHeight * 4),
  };
  layer(brandMask, wordmark, 0, 0, layout.brandWidth, brandHeight);
  moldMask(image, brandMask, brandX, layout.brandY, blend);
  const lettering = metadataMask(
    `${options.language.toUpperCase()} / ${options.display.replace("x", " x ")}`,
  );
  moldMask(
    image,
    lettering,
    Math.floor((image.width - lettering.width) / 2),
    layout.detailY,
    blend,
  );
  return encodeCoverPng(image);
}

async function readInput(path) {
  const file = await open(path, "r");
  try {
    const info = await file.stat();
    requireValue(
      info.isFile() && info.size <= maxInputBytes,
      "input must be a PNG file of at most 32 MiB",
    );
    const bytes = Buffer.alloc(info.size);
    let offset = 0;
    while (offset < bytes.length) {
      const { bytesRead } = await file.read(bytes, offset, bytes.length - offset, offset);
      requireValue(bytesRead > 0, "input changed while reading");
      offset += bytesRead;
    }
    return { bytes, info };
  } finally {
    await file.close();
  }
}

export async function createCover(options, assets) {
  const input = resolve(options.input),
    output = resolve(options.output);
  requireValue(input !== output, "output cannot overwrite the sticker");
  const source = await readInput(input);
  const previous = await lstat(output).catch((error) => {
    if (error.code !== "ENOENT") {
      throw error;
    }
    return null;
  });
  if (previous) {
    requireValue(previous.isFile(), "output must not be a link, directory or special file");
    requireValue(
      previous.dev !== source.info.dev || previous.ino !== source.info.ino,
      "output cannot alias the sticker",
    );
    requireValue(options.force, "output exists; choose another path or use --force");
    const existing = await readInput(output);
    requireValue(
      !chunks(existing.bytes).some((part) => part.type === "caRt"),
      "output is a packed cartridge; choose a separate cover path",
    );
  }
  const bytes = composeCover(source.bytes, assets, options);
  await mkdir(dirname(output), { recursive: true });
  const temporary = `${output}.${randomUUID()}.tmp`;
  const file = await open(temporary, "wx");
  try {
    await file.writeFile(bytes);
    await file.close();
    if (options.force) {
      await rename(temporary, output);
    } else {
      await link(temporary, output);
    }
  } finally {
    await file.close();
    await rm(temporary, { force: true });
  }
  return output;
}

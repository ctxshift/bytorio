// A small geometric stroke alphabet for cartridge metadata. These are vector
// centerlines, sampled analytically with antialiasing, not a pixel-art font.
const paths = {
  L: [
    [
      [0, 0],
      [0, 1],
      [0.7, 1],
    ],
  ],
  U: [
    [
      [0, 0],
      [0, 0.76],
      [0.05, 0.9],
      [0.18, 1],
      [0.52, 1],
      [0.65, 0.9],
      [0.7, 0.76],
      [0.7, 0],
    ],
  ],
  A: [
    [
      [0, 1],
      [0.35, 0],
      [0.7, 1],
    ],
    [
      [0.12, 0.66],
      [0.58, 0.66],
    ],
  ],
  I: [
    [
      [0.35, 0],
      [0.35, 1],
    ],
  ],
  N: [
    [
      [0, 1],
      [0, 0],
      [0.7, 1],
      [0.7, 0],
    ],
  ],
  D: [
    [
      [0, 1],
      [0, 0],
      [0.35, 0],
      [0.58, 0.12],
      [0.7, 0.32],
      [0.7, 0.68],
      [0.58, 0.88],
      [0.35, 1],
      [0, 1],
    ],
  ],
  1: [
    [
      [0.15, 0.18],
      [0.35, 0],
      [0.35, 1],
    ],
    [
      [0.1, 1],
      [0.6, 1],
    ],
  ],
  2: [
    [
      [0, 0.18],
      [0.12, 0.04],
      [0.35, 0],
      [0.58, 0.04],
      [0.7, 0.18],
      [0.7, 0.35],
      [0, 1],
      [0.7, 1],
    ],
  ],
  3: [
    [
      [0, 0.08],
      [0.35, 0],
      [0.6, 0.08],
      [0.7, 0.24],
      [0.6, 0.42],
      [0.35, 0.5],
      [0.6, 0.58],
      [0.7, 0.76],
      [0.6, 0.92],
      [0.35, 1],
      [0, 0.92],
    ],
  ],
  4: [
    [
      [0.55, 1],
      [0.55, 0],
      [0, 0.7],
      [0.7, 0.7],
    ],
  ],
  6: [
    [
      [0.65, 0.04],
      [0.4, 0],
      [0.15, 0.12],
      [0, 0.4],
      [0, 0.78],
      [0.15, 1],
      [0.5, 1],
      [0.7, 0.8],
      [0.7, 0.6],
      [0.5, 0.45],
      [0.15, 0.45],
      [0, 0.6],
    ],
  ],
  8: [
    [
      [0.15, 0],
      [0.55, 0],
      [0.7, 0.15],
      [0.7, 0.32],
      [0.5, 0.5],
      [0.15, 0.5],
      [0, 0.68],
      [0, 0.85],
      [0.15, 1],
      [0.55, 1],
      [0.7, 0.85],
      [0.7, 0.68],
      [0.5, 0.5],
      [0.15, 0.5],
      [0, 0.32],
      [0, 0.15],
      [0.15, 0],
    ],
  ],
  x: [
    [
      [0.08, 0.35],
      [0.62, 1],
    ],
    [
      [0.62, 0.35],
      [0.08, 1],
    ],
  ],
  "/": [
    [
      [0.1, 1.05],
      [0.6, -0.05],
    ],
  ],
};
const oval = Array.from({ length: 33 }, (_, i) => {
  const angle = (i * Math.PI) / 16;
  return [0.35 + Math.cos(angle) * 0.35, 0.5 + Math.sin(angle) * 0.5];
});
paths.O = [oval];
paths[0] = [oval];

export function metadataMask(text, height = 18) {
  const advance = height * 1.05;
  const padding = 3;
  const width = Math.ceil((text.length - 1) * advance + height * 0.7 + padding * 2);
  const rows = height + padding * 2;
  const pixels = Buffer.alloc(width * rows * 4);
  const radius = 0.95;
  for (const [index, letter] of [...text].entries()) {
    if (letter === " ") {
      continue;
    }
    if (!paths[letter]) {
      throw new Error(`Unsupported cartridge lettering: ${letter}`);
    }
    for (const path of paths[letter]) {
      for (let i = 1; i < path.length; i++) {
        const ax = padding + index * advance + path[i - 1][0] * height;
        const ay = padding + path[i - 1][1] * height;
        const bx = padding + index * advance + path[i][0] * height;
        const by = padding + path[i][1] * height;
        const dx = bx - ax,
          dy = by - ay;
        for (
          let y = Math.max(0, Math.floor(Math.min(ay, by) - 2));
          y <= Math.min(rows - 1, Math.ceil(Math.max(ay, by) + 2));
          y++
        ) {
          for (
            let x = Math.max(0, Math.floor(Math.min(ax, bx) - 2));
            x <= Math.min(width - 1, Math.ceil(Math.max(ax, bx) + 2));
            x++
          ) {
            const t = Math.max(
              0,
              Math.min(1, ((x + 0.5 - ax) * dx + (y + 0.5 - ay) * dy) / (dx * dx + dy * dy)),
            );
            const distance = Math.hypot(x + 0.5 - ax - t * dx, y + 0.5 - ay - t * dy);
            const coverage = Math.round(Math.max(0, Math.min(1, radius + 0.5 - distance)) * 255);
            const at = (y * width + x) * 4 + 3;
            pixels[at] = Math.max(pixels[at], coverage);
          }
        }
      }
    }
  }
  return { width, height: rows, pixels };
}

// A recessed face with an upper-left inner shadow and a lower-right lip. Only
// the original logo's alpha is used, so no red/white printed color survives.
export function moldMask(destination, mask, left, top, blend) {
  const alpha = (x, y) =>
    x >= 0 && y >= 0 && x < mask.width && y < mask.height
      ? mask.pixels[(y * mask.width + x) * 4 + 3] / 255
      : 0;
  for (let y = -1; y <= mask.height; y++) {
    for (let x = -1; x <= mask.width; x++) {
      const current = alpha(x, y);
      const previous = alpha(x - 1, y - 1);
      const lip = Math.max(0, previous - current);
      if (lip > 0) {
        blend(destination, left + x, top + y, [130, 133, 139, lip * 140]);
      }
      if (current > 0) {
        const shadow = Math.max(0, current - previous);
        const shade = Math.round(49 - shadow * 24);
        blend(destination, left + x, top + y, [shade, shade + 2, shade + 5, current * 245]);
      }
    }
  }
}

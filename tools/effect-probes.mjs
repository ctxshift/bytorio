// Executed in the built player's page by the conformance runner.
export async function browserEffectProbes() {
  const { createGpu, normalizeGraphics } = await import("./gpu.js");
  const results = [];
  for (const ssaa of ["off", "2x", "1080p"]) {
    const device = await createGpu(normalizeGraphics({ backend: "gpu", ssaa }));
    try {
      const memory = new WebAssembly.Memory({ initial: 1 });
      const vertices = new Float32Array(memory.buffer, 0, 54);
      const positions = [
        [-0.8, -0.8],
        [0, 0.8],
        [0.8, -0.8],
      ];
      for (let i = 0; i < 6; i++) {
        vertices.set([...positions[i % 3], 0.25, 1, 255, 255, 255, 0, 0], i * 9);
      }
      const color = 4096,
        depth = 8192,
        texture = 12288;
      new Uint8Array(memory.buffer, texture, 4).set([128, 0, 0, 128]);
      const packed = new DataView(memory.buffer);
      const center = (16 * 32 + 16) * 4;
      const expected = [0xff3f00c0, 0xffff00ff, 0xff7f0080, 0xffff0000, 0xff3f00c0, 0xff3f00c0];
      for (let scenario = 0; scenario < expected.length; scenario++) {
        for (let i = 0; i < 6; i++) {
          vertices[i * 9 + 2] = scenario === 5 ? 1 : 0.25;
        }
        for (let at = 0; at < 32 * 32 * 4; at += 4) {
          packed.setUint32(color + at, 0xffff0000, true);
          packed.setFloat32(depth + at, scenario >= 3 ? 0.1 : 1, true);
        }
        device.queueTexture(
          texture,
          1,
          1,
          900,
          0,
          0,
          0,
          0,
          0,
          1,
          Number(scenario === 1),
          Number(scenario >= 4),
          Number(scenario !== 2),
        );
        if (
          device.raster(memory, 0, 6, color, depth, 32, 32, 0, 0, 32, 32, 0xff000000, 1, 2) !== 1
        ) {
          throw new Error("Effect probe GPU draw failed");
        }
        const actual = packed.getUint32(color + center, true);
        for (let channel = 0; channel < 4; channel++) {
          const a = (actual >>> (channel * 8)) & 255;
          const b = (expected[scenario] >>> (channel * 8)) & 255;
          if (Math.abs(a - b) > 1) {
            throw new Error(`Effect blend ${ssaa}/${scenario}: ${actual.toString(16)}`);
          }
        }
        const expectedDepth = scenario === 2 ? 0.25 : scenario >= 3 ? 0.1 : 1;
        if (Math.abs(packed.getFloat32(depth + center, true) - expectedDepth) > 0.00001) {
          throw new Error("Effect depth probe failed");
        }
        results.push({ ssaa, scenario, actual });
      }
    } finally {
      device.close();
    }
  }
  return results;
}

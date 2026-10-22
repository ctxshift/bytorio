// Throwaway integration probe. Downloads and generated media remain in build/.
import { mkdir, writeFile, readFile, copyFile } from "node:fs/promises";
import { existsSync, openSync, writeSync, closeSync } from "node:fs";
import { resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";

export const root = resolve("build/vorbis-prototype");
export const source = resolve("experiments/vorbis-prototype");
await mkdir(root, { recursive: true });
function run(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8", timeout: 300000 });
  if (result.status !== 0) {
    throw new Error(`${command}: ${result.stderr}\n${result.stdout}`);
  }
}
const prefix = resolve(root, "install");
const hashes = {};
const expectedHashes = {
  libogg: "c4d91be36fc8e54deae7575241e03f4211eb102afb3fc0775fbbc1b740016705",
  libvorbis: "b33cc4934322bcbf6efcbacf49e3ca01aadbea4114ec9589d1b1e9d20f72954b",
};
for (const [name, version] of [
  ["libogg", "1.3.5"],
  ["libvorbis", "1.3.7"],
]) {
  const archive = resolve(root, `${name}-${version}.tar.xz`);
  if (!existsSync(archive)) {
    const response = await fetch(
      `https://downloads.xiph.org/releases/${name === "libogg" ? "ogg" : "vorbis"}/${name}-${version}.tar.xz`,
      { signal: AbortSignal.timeout(120000) },
    );
    if (!response.ok) {
      throw new Error(`Download failed: ${response.status}`);
    }
    await writeFile(archive, Buffer.from(await response.arrayBuffer()));
  }
  hashes[name] = createHash("sha256")
    .update(await readFile(archive))
    .digest("hex");
  if (hashes[name] !== expectedHashes[name]) {
    throw new Error(`Archive checksum mismatch: ${name}`);
  }
  const folder = resolve(root, `${name}-${version}`);
  if (!existsSync(folder)) {
    run("tar", ["-xf", archive, "-C", root]);
  }
  const build = resolve(root, `${name}-build`);
  run("cmake", [
    "-S",
    folder,
    "-B",
    build,
    "-A",
    "x64",
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
    `-DCMAKE_INSTALL_PREFIX=${prefix}`,
    `-DCMAKE_PREFIX_PATH=${prefix}`,
    "-DBUILD_TESTING=OFF",
    "-DBUILD_SHARED_LIBS=OFF",
  ]);
  run("cmake", ["--build", build, "--config", "Release", "--target", "install", "--parallel", "4"]);
}
run("cmake", [
  "-S",
  source,
  "-B",
  resolve(root, "native-build"),
  "-A",
  "x64",
  `-DCMAKE_PREFIX_PATH=${prefix}`,
]);
run("cmake", ["--build", resolve(root, "native-build"), "--config", "Release", "--parallel", "4"]);
const web = resolve(root, "web");
await mkdir(web, { recursive: true });
const vorbisSources = [
  "mdct",
  "smallft",
  "block",
  "envelope",
  "window",
  "lsp",
  "lpc",
  "analysis",
  "synthesis",
  "psy",
  "info",
  "floor1",
  "floor0",
  "res0",
  "mapping0",
  "registry",
  "codebook",
  "sharedbook",
  "lookup",
  "bitrate",
  "vorbisfile",
];
run("emcc", [
  resolve(source, "wasm.c"),
  ...vorbisSources.map((name) => resolve(root, `libvorbis-1.3.7/lib/${name}.c`)),
  resolve(root, "libogg-1.3.5/src/bitwise.c"),
  resolve(root, "libogg-1.3.5/src/framing.c"),
  `-I${resolve(root, "libvorbis-1.3.7/include")}`,
  `-I${resolve(root, "libogg-1.3.5/include")}`,
  `-I${resolve(root, "install/include")}`,
  "-O3",
  "-sMODULARIZE=1",
  "-sEXPORT_ES6=1",
  "-sENVIRONMENT=worker",
  "-sFILESYSTEM=0",
  "-sINITIAL_MEMORY=8388608",
  "-sALLOW_MEMORY_GROWTH=0",
  "-sEXPORTED_FUNCTIONS=['_malloc','_free']",
  "-sEXPORTED_RUNTIME_METHODS=['HEAPU8','HEAPF32']",
  "-o",
  resolve(web, "vorbis-module.js"),
]);
for (const [name, rate, channels, seconds] of [
  ["music", 48000, 2, 180],
  ["mono", 44100, 1, 8],
]) {
  const wav = resolve(root, `${name}.wav`);
  const ogg = resolve(web, `${name}.ogg`);
  if (!existsSync(ogg)) {
    const frames = rate * seconds;
    const header = Buffer.alloc(44);
    header.write("RIFF");
    header.writeUInt32LE(36 + frames * channels * 2, 4);
    header.write("WAVEfmt ", 8);
    header.writeUInt32LE(16, 16);
    header.writeUInt16LE(1, 20);
    header.writeUInt16LE(channels, 22);
    header.writeUInt32LE(rate, 24);
    header.writeUInt32LE(rate * channels * 2, 28);
    header.writeUInt16LE(channels * 2, 32);
    header.writeUInt16LE(16, 34);
    header.write("data", 36);
    header.writeUInt32LE(frames * channels * 2, 40);
    const fd = openSync(wav, "w");
    writeSync(fd, header);
    const block = Buffer.alloc(rate * channels * 2);
    let random = 12345;
    for (let second = 0; second < seconds; second++) {
      for (let i = 0; i < rate; i++) {
        const t = second + i / rate;
        const note = [220, 261.625565, 329.627557, 293.664768][Math.floor(t * 2) % 4];
        random = (Math.imul(random, 1664525) + 1013904223) >>> 0;
        const drum = ((random / 4294967296) * 2 - 1) * Math.exp(-(t % 0.5) * 30) * 0.18;
        for (let channel = 0; channel < channels; channel++) {
          const signal =
            0.2 * Math.sin(2 * Math.PI * note * t) +
            0.12 * Math.sin(2 * Math.PI * (110 + channel * 55) * t) +
            drum;
          block.writeInt16LE(Math.round(signal * 32767), (i * channels + channel) * 2);
        }
      }
      writeSync(fd, block);
    }
    closeSync(fd);
    run("ffmpeg", ["-v", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", "4", ogg]);
  }
  run("ffmpeg", [
    "-v",
    "error",
    "-y",
    "-c:a",
    "vorbis",
    "-i",
    ogg,
    "-f",
    "f32le",
    resolve(root, `${name}-reference.f32`),
  ]);
}
await copyFile(
  resolve(source, "node_modules/@wasm-audio-decoders/ogg-vorbis/dist/ogg-vorbis-decoder.min.js"),
  resolve(web, "decoder.js"),
);
for (const file of ["index.html", "browser.js", "worklet.js", "wasm-worker.js", "wasm-client.js"]) {
  await copyFile(resolve(source, file), resolve(web, file));
}
await writeFile(
  resolve(root, "dependencies.json"),
  JSON.stringify(
    {
      libogg: "1.3.5",
      libvorbis: "1.3.7",
      browserPackage: "0.1.20",
      hashes,
      ffmpeg: spawnSync("ffmpeg", ["-version"], { encoding: "utf8" }).stdout.split("\n")[0],
    },
    null,
    2,
  ),
);
console.log("Built native decoder, browser probe, and deterministic Vorbis fixtures.");

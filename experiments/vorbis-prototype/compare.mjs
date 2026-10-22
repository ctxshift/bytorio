// Fresh browser process per candidate. Capture overhead and fixtures are identical.
import { createServer } from "node:http";
import { readFile, writeFile, appendFile, mkdir, rm } from "node:fs/promises";
import { resolve, extname } from "node:path";
import { spawnSync, execFile } from "node:child_process";
import { promisify } from "node:util";
import { once } from "node:events";
import { chromium } from "playwright";

const root = resolve("build/vorbis-prototype");
const captures = resolve(root, "comparison-captures");
await mkdir(captures, { recursive: true });
const report = { status: "running", candidates: {}, native: {} };
for (const name of ["music", "mono"]) {
  const run = spawnSync(
    resolve(root, "native-build/Release/vorbis-probe.exe"),
    [resolve(root, `web/${name}.ogg`), resolve(captures, `${name}-native.f32`), "0"],
    { encoding: "utf8", timeout: 120000 },
  );
  if (run.status !== 0) {
    throw new Error(`Native failed: ${run.stderr}`);
  }
  report.native[name] = JSON.parse(run.stdout);
}
const server = createServer(async (request, response) => {
  try {
    const pathname = new URL(request.url, "http://localhost").pathname;
    if (request.method === "POST" && /^\/capture\/[a-z0-9-]+\.f32$/.test(pathname)) {
      for await (const chunk of request) {
        await appendFile(resolve(captures, pathname.split("/").at(-1)), chunk);
      }
      response.writeHead(200).end();
      return;
    }
    const name = pathname === "/" ? "index.html" : pathname.slice(1);
    if (!/^[a-z0-9.-]+$/.test(name)) {
      response.writeHead(404).end();
      return;
    }
    response.setHeader(
      "Content-Type",
      { ".html": "text/html", ".js": "text/javascript", ".wasm": "application/wasm" }[
        extname(name)
      ] ?? "application/octet-stream",
    );
    response.end(await readFile(resolve(root, "web", name)));
  } catch {
    response.writeHead(500).end();
  }
});
server.listen(0, "127.0.0.1");
await once(server, "listening");
const runFile = promisify(execFile);
function compare(actual, expected) {
  const a = new Float32Array(actual.buffer, actual.byteOffset, actual.length / 4);
  const b = new Float32Array(expected.buffer, expected.byteOffset, expected.length / 4);
  let max = 0;
  for (let i = 0; i < Math.min(a.length, b.length); i++) {
    max = Math.max(max, Math.abs(a[i] - b[i]));
  }
  return {
    actualSamples: a.length,
    expectedSamples: b.length,
    maxAbsoluteError: max,
    pass: a.length === b.length && Number.isFinite(max) && max < 0.00002,
  };
}
const native = await readFile(resolve(captures, "music-native.f32"));
const region = native.subarray(7212000 * 8, 7332000 * 8);
try {
  for (const backend of ["package", "libvorbisfile"]) {
    const wasm = backend === "libvorbisfile";
    const candidate = (report.candidates[backend] = {
      playback: {},
      decode: {},
      parity: {},
      memory: [],
    });
    const browser = await chromium.launch({
      args: ["--autoplay-policy=no-user-gesture-required", "--enable-precise-memory-info"],
    });
    const system = await browser.newBrowserCDPSession();
    const page = await browser.newPage();
    page.on("pageerror", (error) => console.error(error));
    let sampling = false;
    async function memory(label) {
      if (sampling && label === "sample") {
        return;
      }
      while (sampling) {
        await new Promise((resolve) => setTimeout(resolve, 50));
      }
      sampling = true;
      try {
        const { processInfo } = await system.send("SystemInfo.getProcessInfo");
        const { stdout } = await runFile("powershell.exe", [
          "-NoProfile",
          "-Command",
          `Get-Process -Id ${processInfo.map((p) => p.id).join(",")} -ErrorAction SilentlyContinue | Select-Object PrivateMemorySize64 | ConvertTo-Json -Compress`,
        ]);
        const values = JSON.parse(stdout);
        candidate.memory.push({
          label,
          privateBytes: (Array.isArray(values) ? values : [values]).reduce(
            (sum, p) => sum + p.PrivateMemorySize64,
            0,
          ),
        });
      } finally {
        sampling = false;
      }
    }
    let timer;
    const deadline = setTimeout(() => browser.close(), 300000);
    try {
      await page.goto(`http://127.0.0.1:${server.address().port}/`);
      await memory("baseline");
      timer = setInterval(() => memory("sample").catch(() => {}), 1000);
      for (const [loop, stall, cache] of [
        [false, 0, false],
        [true, 0, false],
        [true, 0, !wasm],
        [false, 250, false],
      ]) {
        const key = `${loop ? "loop" : "stream"}-${stall}-8192${cache ? "-cached" : ""}${wasm ? "-wasm" : ""}`;
        if (candidate.playback[key]) {
          continue;
        }
        const path = resolve(captures, `play-${key}.f32`);
        await rm(path, { force: true });
        candidate.playback[key] = await page.evaluate(
          ([l, s, c, b]) => window.playProbe(l, s, 8192, c, b),
          [loop, stall, cache, backend],
        );
        candidate.parity[key] = compare(
          await readFile(path),
          (loop ? Buffer.concat([region, region, region, region]) : native).subarray(0, 384000 * 8),
        );
        console.log(`${backend} ${key}: ${JSON.stringify(candidate.playback[key])}`);
      }
      for (const [name, loop, repeats] of [
        ["music", false, 1],
        ["music", true, 4],
        ["mono", false, 1],
        ["mono", false, 24],
      ]) {
        const key = `${name}${loop ? "-loop" : ""}`;
        const path = resolve(captures, `${key}-${wasm ? "wasm" : "browser"}.f32`);
        await rm(path, { force: true });
        candidate.decode[`${key}-${repeats}`] = await page.evaluate(
          ([w, n, l, r]) => (w ? window.measureWasm(n, l, r) : window.measureDecode(n, l, r)),
          [wasm, name, loop, repeats],
        );
        const reference = loop
          ? Buffer.concat([region, region, region, region])
          : Buffer.concat(
              Array(repeats).fill(await readFile(resolve(captures, `${name}-native.f32`))),
            );
        candidate.parity[`${key}-${repeats}`] = compare(await readFile(path), reference);
        console.log(
          `${backend} ${key}-${repeats}: parity ${candidate.parity[`${key}-${repeats}`].pass}`,
        );
      }
      if (wasm) {
        candidate.openCloseStress = await page.evaluate(() => window.stressWasm());
      }
      const cdp = await page.context().newCDPSession(page);
      await cdp.send("HeapProfiler.collectGarbage");
      await memory("after-free-and-main-gc");
    } finally {
      clearTimeout(deadline);
      clearInterval(timer);
      while (sampling) {
        await new Promise((resolve) => setTimeout(resolve, 50));
      }
      await browser.close();
    }
  }
  report.status = "complete";
} finally {
  await writeFile(resolve(root, "comparison.json"), JSON.stringify(report, null, 2));
  await new Promise((resolve) => server.close(resolve));
}

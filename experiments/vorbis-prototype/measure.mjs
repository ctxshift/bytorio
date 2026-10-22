// Verification harness for the throwaway prototype, not a production test suite.
import { createServer } from "node:http";
import { readFile, writeFile, mkdir, appendFile, rm } from "node:fs/promises";
import { resolve, extname } from "node:path";
import { spawnSync, execFile } from "node:child_process";
import { promisify } from "node:util";
import { once } from "node:events";
import { chromium } from "playwright";

const root = resolve("build/vorbis-prototype");
const captures = resolve(root, "captures");
await mkdir(captures, { recursive: true });
const report = {
  status: "running",
  native: {},
  browser: {},
  comparisons: {},
  playback: {},
  memory: [],
};
const executable = resolve(root, "native-build/Release/vorbis-probe.exe");
for (const [name, loop] of [
  ["music", false],
  ["mono", false],
  ["music", true],
]) {
  const key = `${name}${loop ? "-loop" : ""}`;
  const output = resolve(captures, `${key}-native.f32`);
  const run = spawnSync(
    executable,
    [resolve(root, `web/${name}.ogg`), output, loop ? "1" : "0", ...(loop ? ["play"] : [])],
    { encoding: "utf8", timeout: 120000 },
  );
  if (run.status !== 0) {
    throw new Error(`Native ${key}: ${run.status} ${run.stderr}`);
  }
  report.native[key] = JSON.parse(run.stdout);
  console.log(`Native ${key}: ${run.stdout.trim()}`);
}
const server = createServer(async (request, response) => {
  try {
    const pathname = new URL(request.url, "http://localhost").pathname;
    if (request.method === "POST" && /^\/capture\/[a-z0-9-]+\.f32$/.test(pathname)) {
      const file = resolve(captures, pathname.split("/").at(-1));
      for await (const chunk of request) {
        await appendFile(file, chunk);
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
      { ".html": "text/html", ".js": "text/javascript" }[extname(name)] ??
        "application/octet-stream",
    );
    response.end(await readFile(resolve(root, "web", name)));
  } catch (error) {
    response.writeHead(500).end(error.message);
  }
});
server.listen(0, "127.0.0.1");
await once(server, "listening");
const browser = await chromium.launch({
  args: ["--autoplay-policy=no-user-gesture-required", "--enable-precise-memory-info"],
});
const system = await browser.newBrowserCDPSession();
const page = await browser.newPage();
page.setDefaultTimeout(180000);
page.on("pageerror", (error) => console.error(error));
const runFile = promisify(execFile);
let measuring = false;
async function memory(label) {
  if (measuring && label === "sample") {
    return;
  }
  while (measuring) {
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  measuring = true;
  try {
    const { processInfo } = await system.send("SystemInfo.getProcessInfo");
    const ids = processInfo.map((process) => process.id);
    const { stdout } = await runFile("powershell.exe", [
      "-NoProfile",
      "-Command",
      `Get-Process -Id ${ids.join(",")} -ErrorAction SilentlyContinue | Select-Object Id,PrivateMemorySize64,WorkingSet64 | ConvertTo-Json -Compress`,
    ]);
    const parsed = JSON.parse(stdout);
    const processes = Array.isArray(parsed) ? parsed : [parsed];
    report.memory.push({
      label,
      privateBytes: processes.reduce((sum, process) => sum + process.PrivateMemorySize64, 0),
      workingSetBytes: processes.reduce((sum, process) => sum + process.WorkingSet64, 0),
      processes: processes.length,
    });
  } finally {
    measuring = false;
  }
}
function compare(actual, expected) {
  const a = new Float32Array(actual.buffer, actual.byteOffset, actual.byteLength / 4);
  const b = new Float32Array(expected.buffer, expected.byteOffset, expected.byteLength / 4);
  let max = 0,
    sum = 0,
    nonfinite = 0;
  for (let i = 0; i < Math.min(a.length, b.length); i++) {
    const difference = Math.abs(a[i] - b[i]);
    if (!Number.isFinite(difference)) {
      nonfinite++;
    }
    max = Math.max(max, difference);
    sum += difference * difference;
  }
  return {
    actualSamples: a.length,
    expectedSamples: b.length,
    maxAbsoluteError: max,
    rmsError: Math.sqrt(sum / Math.min(a.length, b.length)),
    nonfinite,
    pass: a.length === b.length && max < 0.00002 && nonfinite === 0,
  };
}
let sampler;
try {
  await page.goto(`http://127.0.0.1:${server.address().port}/`);
  await memory("baseline");
  sampler = setInterval(() => memory("sample").catch(() => {}), 1000);
  for (const [name, loop, repeats] of [
    ["music", false, 1],
    ["mono", false, 1],
    ["music", true, 4],
  ]) {
    const key = `${name}${loop ? "-loop" : ""}`;
    await rm(resolve(captures, `${key}-browser.f32`), { force: true });
    report.browser[key] = await page.evaluate(
      ([n, l, r]) => window.measureDecode(n, l, r),
      [name, loop, repeats],
    );
    report.comparisons[key] = compare(
      await readFile(resolve(captures, `${key}-browser.f32`)),
      await readFile(resolve(captures, `${key}-native.f32`)),
    );
    if (!loop) {
      report.comparisons[`${key}-reference`] = compare(
        await readFile(resolve(captures, `${key}-native.f32`)),
        await readFile(resolve(root, `${name}-reference.f32`)),
      );
    }
    console.log(
      `Browser ${key}: ${JSON.stringify(report.browser[key])}; parity ${JSON.stringify(report.comparisons[key])}`,
    );
  }
  const fullNative = await readFile(resolve(captures, "music-native.f32"));
  const region = fullNative.subarray(7212000 * 8, 7332000 * 8);
  report.comparisons.nativeLoop = compare(
    await readFile(resolve(captures, "music-loop-native.f32")),
    Buffer.concat([region, region, region, region]),
  );
  const submitted = await readFile(resolve(captures, "music-loop-native.f32.played"));
  report.comparisons.nativePlayback = compare(
    submitted,
    Buffer.concat([region, region, region, region]).subarray(0, submitted.length),
  );
  for (const [loop, stall, capacity, cache] of [
    [false, 0, 8192, false],
    [false, 250, 8192, false],
    [false, 0, 32768, false],
    [true, 0, 32768, false],
    [true, 0, 8192, true],
    [false, 250, 32768, false],
    [false, 1000, 32768, false],
  ]) {
    const key = `${loop ? "loop" : "stream"}-${stall}-${capacity}${cache ? "-cached" : ""}`;
    await rm(resolve(captures, `play-${key}.f32`), { force: true });
    report.playback[key] = await page.evaluate(
      ([l, s, c, k]) => window.playProbe(l, s, c, k),
      [loop, stall, capacity, cache],
    );
    if (!stall) {
      report.comparisons[`play-${key}`] = compare(
        await readFile(resolve(captures, `play-${key}.f32`)),
        (loop ? Buffer.concat([region, region, region, region]) : fullNative).subarray(
          0,
          48000 * 8 * 8,
        ),
      );
    }
    console.log(`Playback ${key}: ${JSON.stringify(report.playback[key])}`);
  }
  await memory("before-reset-stress");
  await rm(resolve(captures, "mono-browser.f32"), { force: true });
  report.browser.resetStress = await page.evaluate(() => window.measureDecode("mono", false, 24));
  const cdp = await page.context().newCDPSession(page);
  await cdp.send("HeapProfiler.collectGarbage");
  await memory("after-reset-stress-and-gc");
  await page.screenshot({ path: resolve(root, "prototype.png") });
  report.status = "complete";
  report.parityPassed = Object.values(report.comparisons).every((result) => result.pass);
  report.decoderParityPassed = Object.entries(report.comparisons)
    .filter(([name]) => !name.startsWith("play-"))
    .every(([, result]) => result.pass);
  report.streamPlaybackPassed = report.playback["stream-0-8192"].underruns === 0;
  report.loopPlaybackPassed = report.playback["loop-0-32768"].underruns === 0;
  report.cachedLoopPlaybackPassed =
    report.playback["loop-0-8192-cached"].underruns === 0 &&
    report.comparisons["play-loop-0-8192-cached"].pass;
} catch (error) {
  report.status = "failed";
  report.error = error.stack;
  throw error;
} finally {
  clearInterval(sampler);
  while (measuring) {
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  await writeFile(resolve(root, "report.json"), JSON.stringify(report, null, 2));
  await browser.close();
  await new Promise((resolve) => server.close(resolve));
}
console.log(`Prototype measurements: ${root}/report.json`);

import { SeekDecoder } from "./wasm-client.js";
const { OggVorbisDecoderWebWorker } = window["ogg-vorbis-decoder"];
const state = document.querySelector("#state");
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const heap = () => performance.memory?.usedJSHeapSize ?? null;
async function upload(name, pcm) {
  const response = await fetch(`/capture/${name}`, { method: "POST", body: pcm });
  if (!response.ok) {
    throw new Error("Capture failed");
  }
}
function interleave(channels) {
  const output = new Float32Array(channels[0].length * channels.length);
  for (let i = 0; i < channels[0].length; i++) {
    for (let ch = 0; ch < channels.length; ch++) {
      output[i * channels.length + ch] = channels[ch][i];
    }
  }
  return output;
}
async function* decode(bytes, decoder, stats) {
  for (let offset = 0; offset < bytes.length; offset += 4096) {
    const start = performance.now();
    const result = await decoder.decode(bytes.subarray(offset, offset + 4096));
    stats.maxDecodeMs = Math.max(stats.maxDecodeMs, performance.now() - start);
    if (result.errors?.length) {
      throw new Error(JSON.stringify(result.errors));
    }
    stats.maxChunkFrames = Math.max(stats.maxChunkFrames, result.samplesDecoded);
    stats.peakJsHeap = Math.max(stats.peakJsHeap, heap() ?? 0);
    if (result.samplesDecoded) {
      yield result;
    }
  }
  const result = await decoder.flush();
  if (result.errors?.length) {
    throw new Error(JSON.stringify(result.errors));
  }
  if (result.samplesDecoded) {
    yield result;
  }
}
function stats() {
  return { maxDecodeMs: 0, maxChunkFrames: 0, peakJsHeap: heap() ?? 0 };
}
window.measureDecode = async function (name, loop = false, repeats = 1) {
  const bytes = new Uint8Array(await (await fetch(`${name}.ogg`)).arrayBuffer());
  const decoder = new OggVorbisDecoderWebWorker();
  await decoder.ready;
  const result = { ...stats(), inputBytes: bytes.length, frames: 0, loopSetupMs: [], passHeap: [] };
  const start = performance.now();
  for (let pass = 0; pass < repeats; pass++) {
    if (pass) {
      await decoder.reset();
    }
    let cursor = 0,
      found = false;
    const seekStart = performance.now();
    for await (const chunk of decode(bytes, decoder, result)) {
      result.rate = chunk.sampleRate;
      result.channels = chunk.channelData.length;
      const first = loop ? 150.25 * chunk.sampleRate : 0;
      const end = loop ? 152.75 * chunk.sampleRate : Infinity;
      const from = Math.max(0, first - cursor),
        to = Math.min(chunk.samplesDecoded, end - cursor);
      if (to > from) {
        if (!found) {
          result.loopSetupMs.push(performance.now() - seekStart);
          found = true;
        }
        const pcm = interleave(chunk.channelData.map((channel) => channel.subarray(from, to)));
        await upload(`${name}${loop ? "-loop" : ""}-browser.f32`, pcm);
        result.frames += to - from;
      }
      cursor += chunk.samplesDecoded;
      if (cursor >= end) {
        break;
      }
    }
    result.passHeap.push(heap());
  }
  result.elapsedMs = performance.now() - start;
  await decoder.free();
  result.afterFreeHeap = heap();
  state.textContent = JSON.stringify(result, null, 2);
  return result;
};
window.playProbe = async function (
  loop = false,
  stallMs = 0,
  capacityFrames = 32768,
  cacheLoop = false,
  backend = "package",
) {
  const context = new AudioContext({ sampleRate: 48000 });
  await context.resume();
  if (context.sampleRate !== 48000) {
    throw new Error("Probe requires 48 kHz context");
  }
  await context.audioWorklet.addModule("worklet.js");
  const node = new AudioWorkletNode(context, "vorbis-probe", {
    outputChannelCount: [2],
    processorOptions: { capacityFrames },
  });
  node.connect(context.destination);
  const bytes = new Uint8Array(await (await fetch("music.ogg")).arrayBuffer());
  const seekable = backend === "libvorbisfile";
  const decoder = seekable ? new SeekDecoder() : new OggVorbisDecoderWebWorker();
  if (seekable) {
    await decoder.open(bytes);
  } else {
    await decoder.ready;
  }
  let consumed = 0,
    sent = 0,
    finished = false,
    started = false,
    stalled = false;
  const result = {
    ...stats(),
    loop,
    stallMs,
    cacheLoop,
    backend,
    loopSetupMs: [],
    ringCapacityFrames: capacityFrames,
    captureBytes: 48000 * 8 * 8,
  };
  const cached = [];
  let doneResolve;
  const done = new Promise((resolve) => {
    doneResolve = resolve;
  });
  node.port.onmessage = ({ data }) => {
    if (data.type === "progress") {
      consumed = data.consumed;
    }
    if (data.type === "done") {
      finished = true;
      doneResolve(data);
    }
  };
  const startedAt = performance.now();
  async function feed() {
    let pass = 0;
    while (!finished) {
      const reuseCache = cacheLoop && pass > 0;
      if (pass++ && !reuseCache && !seekable) {
        await decoder.reset();
      }
      let cursor = seekable && loop ? 150.25 * 48000 : 0,
        found = false;
      const seekStart = performance.now();
      if (seekable) {
        const seek = await decoder.seek(cursor);
        result.seekMs ??= [];
        result.seekMs.push(seek.seekMs);
      }
      for await (const chunk of reuseCache
        ? cached
        : seekable
          ? decodeSeekable(decoder, result)
          : decode(bytes, decoder, result)) {
        const first = loop && !reuseCache ? 150.25 * 48000 : 0,
          end = loop && !reuseCache ? 152.75 * 48000 : Infinity;
        let from = Math.max(0, first - cursor);
        const to = Math.min(chunk.samplesDecoded, end - cursor);
        if (cacheLoop && !reuseCache && to > from) {
          cached.push({
            samplesDecoded: to - from,
            channelData: chunk.channelData.map((channel) => channel.slice(from, to)),
          });
        }
        if (to > from && !found) {
          result.loopSetupMs.push(performance.now() - seekStart);
          found = true;
        }
        while (from < to && !finished) {
          // Account for in-flight messages using total sent minus acknowledged consumption.
          while (sent - consumed >= capacityFrames * 0.75 && !finished) {
            await sleep(5);
          }
          const n = Math.min(1024, to - from);
          const left = chunk.channelData[0].slice(from, from + n),
            right = chunk.channelData[1].slice(from, from + n);
          node.port.postMessage({ type: "pcm", left, right }, [left.buffer, right.buffer]);
          sent += n;
          from += n;
          if (!started && sent >= capacityFrames / 2) {
            node.port.postMessage({ type: "start" });
            started = true;
            result.startupMs = performance.now() - startedAt;
          }
          if (stallMs && !stalled && consumed >= 48000 * 2) {
            stalled = true;
            const endStall = performance.now() + stallMs;
            while (performance.now() < endStall) {
              /* deliberate producer stall */
            }
          }
        }
        cursor += chunk.samplesDecoded;
        if (cursor >= end || finished) {
          break;
        }
      }
    }
  }
  const feeding = feed();
  const rendered = await done;
  await feeding;
  result.loopCacheBytes = cached.reduce((sum, chunk) => sum + chunk.samplesDecoded * 8, 0);
  await upload(
    `play-${loop ? "loop" : "stream"}-${stallMs}-${capacityFrames}${cacheLoop ? "-cached" : ""}${seekable ? "-wasm" : ""}.f32`,
    rendered.capture,
  );
  delete rendered.capture;
  Object.assign(result, rendered);
  result.afterFreeMemory = await decoder.free();
  node.disconnect();
  await context.close();
  state.textContent = JSON.stringify(result, null, 2);
  window.lastPlayback = result;
  return result;
};
for (const [id, loop, stall, capacity = 32768, cache = false, backend = "package"] of [
  ["play", false, 0],
  ["loop", true, 0],
  ["stall", false, 250],
  ["starve", false, 1000],
  ["cached", true, 0, 8192, true],
  ["wasm", true, 0, 8192, false, "libvorbisfile"],
]) {
  document.querySelector(`#${id}`).onclick = () => {
    state.textContent = "Running…";
    window.playProbe(loop, stall, capacity, cache, backend).catch((error) => {
      state.textContent = error.stack;
    });
  };
}

async function* decodeSeekable(decoder, result) {
  while (true) {
    const start = performance.now();
    const chunk = await decoder.read();
    result.maxDecodeMs = Math.max(result.maxDecodeMs, performance.now() - start);
    result.maxChunkFrames = Math.max(result.maxChunkFrames, chunk.frames);
    result.peakJsHeap = Math.max(result.peakJsHeap, heap() ?? 0);
    result.wasmMemory = chunk.memory;
    if (!chunk.frames) {
      return;
    }
    const channelData = Array.from({ length: chunk.channels }, (_, ch) =>
      Float32Array.from({ length: chunk.frames }, (_, i) => chunk.pcm[i * chunk.channels + ch]),
    );
    yield { samplesDecoded: chunk.frames, sampleRate: chunk.rate, channelData };
  }
}

window.measureWasm = async function (name, loop = false, repeats = 1) {
  const bytes = new Uint8Array(await (await fetch(`${name}.ogg`)).arrayBuffer());
  const decoder = new SeekDecoder();
  const result = { ...stats(), frames: 0, seeks: [], inputBytes: bytes.length, cycles: [] };
  const start = performance.now();
  const opened = await decoder.open(bytes);
  result.open = opened;
  for (let pass = 0; pass < repeats; pass++) {
    const first = loop ? 150.25 * opened.rate : 0;
    const end = loop ? 152.75 * opened.rate : Infinity;
    result.seeks.push(await decoder.seek(first));
    let cursor = first;
    for await (const chunk of decodeSeekable(decoder, result)) {
      const count = Math.min(chunk.samplesDecoded, end - cursor);
      await upload(
        `${name}${loop ? "-loop" : ""}-wasm.f32`,
        interleave(chunk.channelData.map((channel) => channel.subarray(0, count))),
      );
      result.frames += count;
      cursor += count;
      if (cursor >= end) {
        break;
      }
    }
    result.cycles.push(result.wasmMemory);
  }
  result.elapsedMs = performance.now() - start;
  result.afterFreeMemory = await decoder.free();
  return result;
};

window.stressWasm = async function () {
  const bytes = new Uint8Array(await (await fetch("music.ogg")).arrayBuffer());
  const decoder = new SeekDecoder();
  const samples = [];
  for (let i = 0; i < 128; i++) {
    await decoder.open(bytes);
    await decoder.seek(7212000);
    await decoder.read();
    samples.push(await decoder.call("close"));
  }
  const final = await decoder.free();
  return { samples, final };
};

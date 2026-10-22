import createVorbis from "./vorbis-module.js";

const module = await createVorbis();
let input = 0;
let channels = 0;
let rate = 0;
let peakUsed = 0;
const baselineUsed = module._probe_used();
function memory() {
  const used = module._probe_used();
  peakUsed = Math.max(peakUsed, used);
  return { used, peakUsed, baselineUsed, heapCapacity: module.HEAPU8.buffer.byteLength };
}
self.onmessage = ({ data }) => {
  try {
    let result;
    if (data.type === "open") {
      module._probe_close();
      if (input) {
        module._free(input);
      }
      input = module._malloc(data.bytes.byteLength);
      if (!input) {
        throw new Error("WASM allocation failed");
      }
      module.HEAPU8.set(data.bytes, input);
      const status = module._probe_open(input, data.bytes.byteLength);
      if (status) {
        throw new Error(`Open: ${status}`);
      }
      channels = module._probe_channels();
      rate = module._probe_rate();
      result = { channels, rate, memory: memory() };
    } else if (data.type === "seek") {
      const start = performance.now();
      const status = module._probe_seek(data.frame);
      if (status) {
        throw new Error(`Seek: ${status}`);
      }
      result = { seekMs: performance.now() - start, memory: memory() };
    } else if (data.type === "read") {
      const frames = module._probe_read(data.count);
      if (frames < 0) {
        throw new Error(`Decode: ${frames}`);
      }
      const offset = module._probe_output() / 4;
      const pcm = module.HEAPF32.slice(offset, offset + frames * channels);
      result = { frames, channels, rate, pcm, memory: memory() };
    } else if (data.type === "close") {
      module._probe_close();
      module._free(input);
      input = 0;
      result = memory();
    }
    self.postMessage({ id: data.id, result }, result?.pcm ? [result.pcm.buffer] : []);
  } catch (error) {
    self.postMessage({ id: data.id, error: error.message });
  }
};
self.postMessage({ ready: true });

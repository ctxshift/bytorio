import { resourceSchema as limits } from "./constants.js";

// Runs on the game Worker. No codec work or refill messages pass through the UI.
export async function createOggPump(runtime) {
  const { default: createDecoder } = await import("./vorbis.js");
  const decoder = await createDecoder();
  const output = decoder._malloc(limits.oggChunkFrames * 8);
  if (!output) {
    throw new Error("Cannot allocate Vorbis output buffer.");
  }
  const slots = Array.from({ length: limits.maxOggStreams }, () => ({
    id: 0,
    handle: 0,
    cursor: 0,
  }));
  return {
    pump() {
      for (const [index, slot] of slots.entries()) {
        for (let chunk = 0; chunk < 8; chunk++) {
          const pointer = runtime.runtime_ogg_request(index);
          const [id, content, cursor, total, low, high, count, bytes, loopStart, loopEnd] =
            new Uint32Array(runtime.memory.buffer, pointer, limits.oggRequestWords);
          if (slot.id !== id) {
            if (slot.handle) {
              decoder._vorbis_close(slot.handle);
            }
            Object.assign(slot, { id, handle: 0, cursor: 0 });
          }
          if (!id) {
            break;
          }
          if (!slot.handle) {
            const input = decoder._malloc(bytes);
            if (!input) {
              throw new Error("Cannot allocate Vorbis input buffer.");
            }
            try {
              decoder.HEAPU8.set(
                new Uint8Array(
                  runtime.memory.buffer,
                  runtime.runtime_content_pointer(content),
                  bytes,
                ),
                input,
              );
              slot.handle = decoder._vorbis_open(input, bytes);
            } finally {
              decoder._free(input);
            }
            if (!slot.handle || decoder._vorbis_frames(slot.handle) !== total) {
              throw new Error("Invalid Vorbis stream.");
            }
          }
          if (!count) {
            if (cursor === total) {
              runtime.runtime_ogg_feed(index, id, low, high, 0);
            }
            break;
          }
          if (slot.cursor !== cursor && decoder._vorbis_seek(slot.handle, cursor) !== 1) {
            throw new Error("Vorbis seek failed.");
          }
          const frames = decoder._vorbis_read(slot.handle, output, count, loopStart, loopEnd);
          if (frames <= 0) {
            throw new Error("Vorbis decoding failed.");
          }
          slot.cursor = cursor + frames;
          if (loopEnd && slot.cursor >= loopEnd) {
            slot.cursor = loopStart + ((slot.cursor - loopEnd) % (loopEnd - loopStart));
          }
          new Float32Array(runtime.memory.buffer, runtime.runtime_ogg_pcm(), frames * 2).set(
            decoder.HEAPF32.subarray(output / 4, output / 4 + frames * 2),
          );
          if (!runtime.runtime_ogg_feed(index, id, low, high, frames)) {
            break;
          }
        }
      }
    },
    close() {
      for (const slot of slots) {
        if (slot.handle) {
          decoder._vorbis_close(slot.handle);
        }
        slot.handle = 0;
      }
      decoder._free(output);
    },
    memoryBytes: decoder.HEAPU8.buffer.byteLength,
  };
}

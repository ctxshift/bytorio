import { decodeCartridge, contentImports } from "./cartridge.js";
import { configureResources, submitResources, loadSource, negotiateProfile } from "./policy.js";
import { createOggPump } from "./ogg.js";

self.onmessage = async () => {
  let pump;
  try {
    const binary = async (path) => (await fetch(path)).arrayBuffer();
    const runtime = (
      await WebAssembly.instantiate(await binary("./runtime.wasm"), { env: { sin: Math.sin } })
    ).instance.exports;
    const cart = decodeCartridge(runtime, await binary("./game.png"));
    const game = (
      await WebAssembly.instantiate(
        cart.language === "odin" ? cart.code : await binary("./luau-executor.wasm"),
        {
          env: {
            ...contentImports(runtime, () => game),
            save_size: () => 0,
            save_status: () => 3,
            save_read: () => 0,
            save_write: () => 3,
            text_configure: () => 0,
            text_read: () => 0,
          },
        },
      )
    ).instance.exports;
    runtime.runtime_init();
    game._initialize?.();
    if (cart.language === "luau") {
      loadSource(game, cart.code);
    }
    negotiateProfile(game, cart);
    configureResources(game, runtime);
    game.game_init();
    submitResources(game, runtime);
    pump = await createOggPump(runtime);
    const mixer = (await WebAssembly.instantiate(await binary("./audio.wasm"), {})).instance
      .exports;
    if (!mixer.audio_init()) {
      throw new Error("Mixer allocation failed");
    }
    const pcm = new Float32Array(96000 * 2);
    for (let frame = 0; frame < pcm.length / 2;) {
      pump.pump();
      for (;;) {
        const size = runtime.runtime_audio_export();
        if (!size) {
          break;
        }
        if (size < 0) {
          throw new Error("Audio export failed");
        }
        new Uint8Array(mixer.memory.buffer, mixer.audio_packet(), size).set(
          new Uint8Array(runtime.memory.buffer, runtime.runtime_audio_packet(), size),
        );
        if (!mixer.audio_submit(size)) {
          throw new Error("Audio import failed");
        }
      }
      const count = Math.min(127, pcm.length / 2 - frame);
      mixer.audio_render(count, 48000);
      pcm.set(
        new Float32Array(mixer.memory.buffer, mixer.audio_output_pointer(), count * 2),
        frame * 2,
      );
      const size = mixer.audio_feedback();
      new Uint8Array(runtime.memory.buffer, runtime.runtime_audio_feedback_pointer(), size).set(
        new Uint8Array(mixer.memory.buffer, mixer.audio_feedback_pointer(), size),
      );
      if (!runtime.runtime_audio_feedback(size)) {
        throw new Error("Feedback failed");
      }
      frame += count;
    }
    self.postMessage({ pcm: pcm.buffer, memoryBytes: pump.memoryBytes }, [pcm.buffer]);
  } catch (error) {
    self.postMessage({ error: error.stack || String(error) });
  } finally {
    pump?.close();
  }
};

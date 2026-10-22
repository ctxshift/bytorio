/* global WebAssembly, fetch, Worker, MessageChannel, setTimeout, clearTimeout */
export async function verifyAdmission(baseline) {
  const mixer = (
    await WebAssembly.instantiate(await (await fetch("./audio.wasm")).arrayBuffer(), {})
  ).instance.exports;
  if (mixer.audio_init() !== 1) {
    throw new Error("Mixer initialization failed");
  }
  const worker = new Worker(baseline ? "./admission-red-worker.js" : "./admission-worker.js", {
    type: "module",
  });
  const channel = new MessageChannel();
  const messages = [];
  const waiters = [];
  const held = [];
  const errors = [];
  let packets = 0;
  const require = (condition, message) => {
    if (!condition) {
      throw new Error(message);
    }
  };
  worker.onerror = (event) => errors.push(event.message);
  worker.onmessage = ({ data }) => {
    if (data.type === "error") {
      errors.push(data.error);
    }
    const index = waiters.findIndex((waiter) => waiter.type === data.type);
    if (index >= 0) {
      const waiter = waiters.splice(index, 1)[0];
      clearTimeout(waiter.timer);
      waiter.resolve(data);
    } else {
      messages.push(data);
    }
  };
  const next = (type) => {
    const index = messages.findIndex((message) => message.type === type);
    if (index >= 0) {
      return Promise.resolve(messages.splice(index, 1)[0]);
    }
    return new Promise((resolve, reject) => {
      const timer = setTimeout(
        () => reject(new Error(`Timed out waiting for ${type}: ${errors.join("; ")}`)),
        5000,
      );
      waiters.push({ type, resolve, timer });
    });
  };
  const observe = () => {
    worker.postMessage({ type: "admission-observe" });
    return next("admission-observation");
  };
  const step = () =>
    worker.postMessage({
      type: "step",
      steps: 1,
      render: false,
      input: { buttons: 0, pointer: false, x: 0, y: 0 },
    });
  channel.port1.onmessage = ({ data }) => {
    if (data.type !== "packet") {
      return;
    }
    new Uint8Array(mixer.memory.buffer, mixer.audio_packet(), data.bytes).set(
      new Uint8Array(data.buffer, 0, data.bytes),
    );
    if (mixer.audio_submit(data.bytes) !== 1) {
      errors.push("Actual mixer rejected a producer packet");
    }
    mixer.audio_render(800, 48000);
    packets++;
    held.push(data);
    // Deliberately withhold these real transferable-buffer credits.
  };
  channel.port1.start();
  try {
    worker.postMessage({ type: "load", gameUrl: "./game.png", graphics: { backend: "cpu" } });
    await next("ready");
    worker.postMessage({ type: "audio-connect", port: channel.port2 }, [channel.port2]);
    channel.port1.postMessage({ type: "ready" });
    let state = await observe();
    let completed = 0;
    while (state.available > 0 && completed < 24) {
      step();
      await next("stepped");
      completed++;
      state = await observe();
    }
    require(state.available === 0, "Real producer batches must be exhausted");
    require(held.length > 0, "Real audio transfer credits must be held");
    require(errors.length === 0, errors.join("; "));
    const before = state.updates;
    step();
    const blocked = await observe();
    if (baseline) {
      require(blocked.updates ===
        before + 1, "Unguarded baseline executes the guest before discovering saturation");
      require(errors.some((error) =>
        /queue|capacity|batch/i.test(error),
      ), "Unguarded baseline must reproduce actual queue rejection");
      return { baseline, completed, packets, before, blocked, errors };
    }
    require(blocked.updates === before, "Saturated admission must postpone the guest update");
    require(errors.length === 0, errors.join("; "));
    const credit = held.shift();
    channel.port1.postMessage({ type: "recycle", id: credit.id, buffer: credit.buffer }, [
      credit.buffer,
    ]);
    await next("stepped");
    const resumed = await observe();
    require(resumed.updates === before + 1, "Releasing credit executes exactly one guest update");
    require(errors.length === 0, errors.join("; "));
    return { baseline, completed, packets, before, blocked, resumed, errors };
  } finally {
    for (const waiter of waiters) {
      clearTimeout(waiter.timer);
    }
    worker.terminate();
    channel.port1.close();
  }
}

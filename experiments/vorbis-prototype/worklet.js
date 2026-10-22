class Probe extends AudioWorkletProcessor {
  constructor(options) {
    super();
    this.capacity = options.processorOptions.capacityFrames;
    this.left = new Float32Array(this.capacity);
    this.right = new Float32Array(this.capacity);
    this.read = 0;
    this.write = 0;
    this.queued = 0;
    this.started = false;
    this.frames = 0;
    this.consumed = 0;
    this.underruns = 0;
    this.maxQueue = 0;
    this.overflows = 0;
    this.capture = new Float32Array(48000 * 8 * 2);
    this.captureFrames = 0;
    this.port.onmessage = ({ data }) => {
      if (data.type === "pcm") {
        const n = data.left.length;
        if (n > this.capacity - this.queued) {
          this.overflows++;
          return;
        }
        for (let i = 0; i < n; i++) {
          this.left[this.write] = data.left[i];
          this.right[this.write] = data.right[i];
          this.write = (this.write + 1) % this.capacity;
        }
        this.queued += n;
        this.maxQueue = Math.max(this.maxQueue, this.queued);
      } else if (data.type === "start") {
        this.started = true;
      }
    };
  }
  process(_inputs, outputs) {
    const out = outputs[0];
    if (!this.started) {
      return true;
    }
    for (let i = 0; i < out[0].length; i++) {
      if (this.frames >= 48000 * 8) {
        break;
      }
      let left = 0,
        right = 0;
      if (this.queued) {
        left = this.left[this.read];
        right = this.right[this.read];
        this.read = (this.read + 1) % this.capacity;
        this.queued--;
        this.consumed++;
      } else {
        this.underruns++;
      }
      out[0][i] = left;
      out[1][i] = right;
      this.capture[this.captureFrames * 2] = left;
      this.capture[this.captureFrames * 2 + 1] = right;
      this.captureFrames++;
      this.frames++;
    }
    if (this.frames >= 48000 * 8) {
      this.port.postMessage(
        {
          type: "done",
          underruns: this.underruns,
          overflows: this.overflows,
          maxQueue: this.maxQueue,
          frames: this.frames,
          capture: this.capture,
        },
        [this.capture.buffer],
      );
      return false;
    }
    if (this.frames % 1024 === 0) {
      this.port.postMessage({
        type: "progress",
        queued: this.queued,
        frames: this.frames,
        consumed: this.consumed,
      });
    }
    return true;
  }
}
registerProcessor("vorbis-probe", Probe);

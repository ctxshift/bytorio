import { resourceSchema as limits } from "./constants.js";

// No game, DOM, file or network access here. All process() views, message objects
// and feedback transfers are allocated during construction/message handling.
class MixerProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();
    this.runtime = new WebAssembly.Instance(options.processorOptions.module, {}).exports;
    this.runtime._initialize?.();
    if (this.runtime.audio_init() !== 1) {
      throw new Error("Cannot preallocate audio mixer.");
    }
    this.output = new Float32Array(
      this.runtime.memory.buffer,
      this.runtime.audio_output_pointer(),
      limits.maxAudioDeviceBlock * 2,
    );
    this.feedback = new Uint8Array(
      this.runtime.memory.buffer,
      this.runtime.audio_feedback_pointer(),
      limits.maxAudioFeedbackBytes,
    );
    this.frames = 0;
    this.audioPort = this.port;
    this.running = true;
    this.primed = !options.processorOptions.waitForProducer;
    this.packetSlots = Array.from({ length: limits.maxAudioTransfers }, (_, id) => ({
      pending: false,
      message: { type: "recycle", id, buffer: null },
      transfer: [null],
    }));
    this.failure = { type: "error", error: "Audio mixer queue or block was invalid." };
    this.slots = Array.from({ length: limits.maxAudioTransfers }, (_, id) => {
      const buffer = new ArrayBuffer(limits.maxAudioFeedbackBytes);
      return {
        buffer,
        view: new Uint8Array(buffer),
        message: { type: "feedback", id, buffer, bytes: 0 },
        transfer: [buffer],
      };
    });
    this.port.onmessage = ({ data }) => {
      if (data.type === "worker-port") {
        this.audioPort = data.port;
        this.audioPort.onmessage = this.port.onmessage;
        this.audioPort.postMessage({ type: "ready" });
      } else if (data.type === "start") {
        this.primed = true;
      } else if (data.type === "packet") {
        const packetSlot = this.packetSlots[data.id];
        if (
          !packetSlot ||
          packetSlot.pending ||
          !Number.isInteger(data.bytes) ||
          data.bytes < limits.audioPacketHeaderBytes ||
          data.bytes > limits.maxAudioPacketBytes ||
          data.bytes > data.buffer.byteLength
        ) {
          this.running = false;
          this.port.postMessage(this.failure);
          return;
        }
        new Uint8Array(this.runtime.memory.buffer, this.runtime.audio_packet(), data.bytes).set(
          new Uint8Array(data.buffer, 0, data.bytes),
        );
        if (this.runtime.audio_submit(data.bytes) !== 1) {
          this.running = false;
          this.failure.error = "Audio mixer rejected an incoming command packet.";
          this.port.postMessage(this.failure);
          return;
        }
        // Return producer credits only after process() drains the batch queue.
        // Immediate recycling can let a refill burst overrun its eight slots.
        packetSlot.message.buffer = data.buffer;
        packetSlot.transfer[0] = data.buffer;
        packetSlot.pending = true;
      } else if (data.type === "feedback-recycle") {
        const slot = this.slots[data.id];
        if (!slot || slot.buffer || data.buffer.byteLength !== limits.maxAudioFeedbackBytes) {
          this.running = false;
          this.failure.error = "Audio mixer received an invalid feedback recycle.";
          this.port.postMessage(this.failure);
          return;
        }
        slot.buffer = data.buffer;
        slot.view = new Uint8Array(data.buffer);
        slot.message.buffer = data.buffer;
        slot.transfer[0] = data.buffer;
      } else if (data.type === "pause") {
        this.runtime.audio_pause(Number(data.paused));
      } else if (data.type === "close") {
        this.running = false;
        if (this.audioPort !== this.port) {
          this.audioPort.close();
        }
        this.port.postMessage({ type: "closed" });
      }
    };
    this.port.postMessage({ type: "ready", rate: sampleRate, leadFrames: limits.audioLeadFrames });
  }

  process(_inputs, outputs) {
    if (!this.running) {
      return false;
    }
    const channels = outputs[0];
    if (channels.length !== 2 || channels[0].length > limits.maxAudioDeviceBlock) {
      this.port.postMessage(this.failure);
      return false;
    }
    const frames = channels[0].length;
    if (!this.primed) {
      this.runtime.audio_consume();
    } else if (!this.runtime.audio_render(frames, sampleRate)) {
      this.port.postMessage(this.failure);
      return false;
    }
    for (const slot of this.packetSlots) {
      if (slot.pending) {
        this.audioPort.postMessage(slot.message, slot.transfer);
        slot.pending = false;
        slot.message.buffer = null;
        slot.transfer[0] = null;
      }
    }
    for (let i = 0; i < frames; i++) {
      channels[0][i] = this.primed ? this.output[i * 2] : 0;
      channels[1][i] = this.primed ? this.output[i * 2 + 1] : 0;
    }
    this.frames += frames;
    if (this.frames >= sampleRate / 60) {
      for (let id = 0; id < this.slots.length; id++) {
        const slot = this.slots[id];
        if (!slot.buffer) {
          continue;
        }
        const size = this.runtime.audio_feedback();
        for (let i = 0; i < size; i++) {
          slot.view[i] = this.feedback[i];
        }
        slot.message.bytes = size;
        this.audioPort.postMessage(slot.message, slot.transfer);
        slot.buffer = null;
        this.frames = 0;
        break;
      }
    }
    return true;
  }
}

registerProcessor("console-pcm-mixer", MixerProcessor);

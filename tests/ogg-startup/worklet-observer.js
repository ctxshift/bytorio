/* global MixerProcessor, registerProcessor */

// Appended only to the copied production worklet. This observes its actual
// output without changing scheduling, packet handling, rendering or the clock.
class StartupObservedMixer extends MixerProcessor {
  constructor(options) {
    super(options);
    this.startupSamples = new Float32Array(96000 * 2);
    this.startupFrames = 0;
  }

  process(inputs, outputs) {
    const running = super.process(inputs, outputs);
    if (this.primed && this.startupSamples) {
      const channels = outputs[0];
      const count = Math.min(channels[0].length, 96000 - this.startupFrames);
      for (let frame = 0; frame < count; frame++) {
        const target = (this.startupFrames + frame) * 2;
        this.startupSamples[target] = channels[0][frame];
        this.startupSamples[target + 1] = channels[1][frame];
      }
      this.startupFrames += count;
      if (this.startupFrames === 96000) {
        const buffer = this.startupSamples.buffer;
        this.port.postMessage({ type: "startup-pcm", buffer }, [buffer]);
        this.startupSamples = null;
      }
    }
    return running;
  }
}

registerProcessor("console-pcm-mixer", StartupObservedMixer);

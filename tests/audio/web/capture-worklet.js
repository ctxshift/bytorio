class Capture extends AudioWorkletProcessor {
  constructor() {
    super();
    this.pcm = new Float32Array(48000 * 2);
    this.at = 0;
    this.sent = false;
    this.message = { pcm: this.pcm.buffer };
    this.transfer = [this.pcm.buffer];
  }

  process(inputs, outputs) {
    const source = inputs[0];
    if (source.length < 2) {
      return true;
    }
    for (let i = 0; i < source[0].length; i++) {
      if (this.at < this.pcm.length) {
        this.pcm[this.at++] = source[0][i];
        this.pcm[this.at++] = source[1][i];
      }
    }
    for (let c = 0; c < outputs[0].length; c++) {
      outputs[0][c].fill(0);
    }
    if (this.at === this.pcm.length && !this.sent) {
      this.sent = true;
      this.port.postMessage(this.message, this.transfer);
    }
    return true;
  }
}
registerProcessor("capture", Capture);

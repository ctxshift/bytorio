export class SeekDecoder {
  constructor() {
    this.worker = new Worker("wasm-worker.js", { type: "module" });
    this.pending = new Map();
    this.nextId = 0;
    let readyResolve;
    this.ready = new Promise((resolve) => {
      readyResolve = resolve;
    });
    this.worker.onmessage = ({ data }) => {
      if (data.ready) {
        readyResolve();
        return;
      }
      const pending = this.pending.get(data.id);
      if (!pending) {
        return;
      }
      this.pending.delete(data.id);
      clearTimeout(pending.timer);
      if (data.error) {
        pending.reject(new Error(data.error));
      } else {
        pending.resolve(data.result);
      }
    };
  }
  async call(type, args = {}) {
    await this.ready;
    return new Promise((resolve, reject) => {
      const id = this.nextId++;
      const timer = setTimeout(() => {
        this.pending.delete(id);
        this.worker.terminate();
        reject(new Error(`Worker timeout: ${type}`));
      }, 30000);
      this.pending.set(id, { resolve, reject, timer });
      this.worker.postMessage({ id, type, ...args });
    });
  }
  async open(bytes) {
    return this.call("open", { bytes });
  }
  async seek(frame) {
    return this.call("seek", { frame });
  }
  async read(count = 1024) {
    return this.call("read", { count });
  }
  async free() {
    const result = await this.call("close");
    this.worker.terminate();
    return result;
  }
}

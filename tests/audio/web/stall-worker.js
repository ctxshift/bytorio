self.onmessage = () => {
  const started = performance.now();
  while (performance.now() - started < 500) {
    // Simulate a game producer that stops submitting commands for 500 ms.
  }
  self.postMessage("finished");
};

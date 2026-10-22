// Appended only to copied workers. All production scheduling remains intact;
// this diagnostic reads counters without changing guest/runtime state.
/* global game, runtime, self */
const admissionHandler = self.onmessage;
let admissionGuest;
self.onmessage = (event) => {
  if (event.data.type === "admission-observe") {
    // Retain only a diagnostic reference: the controlled failure clears the
    // production game binding before this observer can inspect its counter.
    admissionGuest ||= game;
    self.postMessage({
      type: "admission-observation",
      updates: admissionGuest.admission_updates(),
      available: runtime?.runtime_audio_batches_available() ?? -1,
    });
    return;
  }
  return admissionHandler(event);
};

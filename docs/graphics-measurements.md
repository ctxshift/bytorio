# Software graphics measurement method

Run `npm run test:graphics` on the supported Windows development host. Correctness
checks are mandatory; performance numbers are recorded without hardware-dependent
pass/fail thresholds. The full records, timing samples and captures are retained
under `build/graphics-verification/<run>/report.json`.

The conformance scene compares Luau and Odin, standalone native playback, the
native Wasmtime adapter and actual browser Workers. Complete native/browser
RGBA buffers must match for 13 frames. It covers stencil masks, source-over/add,
indexed LUT composition, mutable palettes, row effects, affine/nearest sampling,
offscreen passes, legacy sprites/text within a pass, asynchronous readback and
320x180 to 640x360 mode changes. Native unit fixtures additionally check exact
edge pixels, flips, tint, color-channel masks, copy, overlapping CPU buffers,
submission snapshots, completion backpressure and transactional rollback.

The upload workload changes every byte of a 640x360 premultiplied RGBA buffer,
uploads it, and presents it through the shared software renderer. This is
921,600 logical upload bytes per frame, or 55,296,000 bytes/second at 60 Hz.
It deliberately includes SDK serialization and validation, rather than timing
only a raw host memcpy.

- Native runs 120 updates paced toward 60 Hz. The summary discards the first 20
  CPU samples, then reports median/p95 of update, transport and rendering work.
  Sleeps, hashing, capture I/O, SDL texture delivery and physical scanout are
  excluded from CPU timing. Reported pacing measures the verifier, not a display.
- Browser CPU samples come from seven 120-frame passes, discarding two warm-up
  passes. The reported CPU total includes update, transport, draw submission and
  rasterization. Pixel extraction into the display transfer buffer is reported
  separately. A second 120-frame run uses animation-frame pacing and Canvas
  delivery, recording worker round-trip/Canvas time and delivered cadence.
  Headless Canvas delivery does not measure a physical monitor's scanout latency.
- Native and browser upload traces must match. Timing samples may differ with
  scheduling, browser versions, thermal state and unrelated machine load.

`packetBytesPerFrame` measures accepted wire bytes across control and draw.
`hostCopyBytesPerFrame` counts the host packet snapshot, resource copy-on-write,
upload/copy/readback bytes, and copying the final image into the display surface.
It excludes SDK staging/compaction, mailbox delivery, allocation zeroing, per-pixel
compositing reads/writes and the browser's display-transfer copy. It is not a
complete memory-bandwidth measurement. The SDK additionally copies a full upload
into staging and compacts it into the submitted packet.

For this upload-only steady state the measured packet is 921,856 bytes/frame
(921,728 control plus 128 presentation). Tracked host copies total 3,686,656
bytes/frame. Adding SDK staging and compaction gives at least 5,529,856 explicitly
copied bytes/frame before the browser's additional 921,600-byte display transfer,
allocation clearing and rendering traffic. Native warm-up normalization excludes
the first small readback-consumption command from the conformance scene.

Memory fields distinguish guest linear memory, tracked Luau allocations, browser
runtime linear memory, live resource bytes and the peak charged resource quota.
Neither linear-memory capacity nor the resource quota is process RSS. The initial
local run used roughly 4.3 MB guest memory for Odin, 4.9 MB for Luau (about 2 MB
tracked heap), 10.9 MB browser runtime memory and a 4.1 MB peak charged resource
budget. Native CPU medians were about 2.2 ms and browser CPU medians 4.2-4.6 ms;
these are a short local reference, not portable frame-time guarantees. Consult
the latest report rather than treating these values as acceptance thresholds.

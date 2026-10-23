# PCM mixer verification

Run `mise run test:audio` on the supported Windows development host. The test
builds real Luau and Odin cartridges, the native trace runner and both browser
modules. Retained projects, raw f32 captures and `results.json` live under
ignored `build/audio-verification/<run>/`. Run `mise run test` for legacy
cartridge, resource, graphics, RPG and racing regression coverage.

The independent reference checks source-rate interpolation, loop endpoints,
linear pan/gain/bus ramps, release timing, one-shot completion, absolute stream
intervals and defined silence. Both SDKs must generate byte-identical prepared
audio commands. Native Wasmtime and browser-target Wasm render 48,000 device
frames at 44,100, 48,000 and 96,000 Hz, with differing block sizes. Every output
sample must agree within 1e-6. The fixture intentionally produces 80 missing
stream voice-frames and four completions; these are expected, not device dropouts.

Native unit checks additionally exercise producer queue exhaustion, all 4,096
event slots, transactional rollback, snapshots surviving source writes and
destruction, bus capacity, stream overlap, block independence, pause/resume and
rendering with a nil allocator. The transport corpus mutates public and prepared
packets, rejects malformed descriptors/PCM/ranges/leases/orders and duplicate
packets, then requires successful recovery. The full 16-voice workload checks
master saturation and constant Wasm linear-memory capacity while rendering.

SDL callback capture uses its dummy driver for reproducibility. The producer
stalls for 500 ms while callbacks continue rendering a sustained loop. An actual
Chromium AudioWorklet captures the same PCM while the main thread and a worker
both busy-wait for 500 ms. This baseline has no shared memory or isolation
headers. The shipped browser player separately tests gesture start, pause,
resume and loading a replacement PNG through its file input in both languages.

The first local run on 2026-10-19 used pinned Odin dev-2026-10, Luau 0.743,
Wasmtime 49.0.3 and Emscripten 6.0.12, with Chromium 156.0.8078.4.
All native/Wasm comparisons and AudioWorklet captures had **zero sample error**.
The 50 ms initial lead was exactly 2,400 silent frames at 48 kHz. Pause held the
logical cursor after its fade; resume advanced the same session with a new epoch;
PNG reload began a fresh epoch. Both SDKs received all four completion records.
Eleven malformed resource packets and nine malformed prepared packets were
rejected atomically. The producer/device stall captured roughly 24,576 frames
before the producer resumed, using SDL's 1,024-frame dummy device buffer.

Offline native rendering took approximately 1.5–3.0 ms for 48,000 output frames
in this small fixture. This is mixer/guest reference work, not speaker latency
or a minimum-device real-time guarantee. The 16-voice Wasm render-and-check
workload took approximately 13–42 ms across the three rates, including JS sample
assertions. Performance timings are recorded without machine-dependent pass/fail
thresholds. Output frames represent differing durations at differing device rates.

The fixture's peak live snapshot pages occupied 5,120 bytes. The standalone DSP
Wasm module reserved about 22 MB linear memory under the 16-voice workload;
linear-memory capacity is not process RSS. Portable resource accounting reserves
52,369,936 bytes for the full browser delivery worst case even on native, plus
ordinary resource storage. This conservative reservation differs from observed
live PCM. The browser controller and DSP have separate 160 MiB / 80 MiB maximum
linear-memory limits, not upfront physical-memory allocations or resource quotas.

Both cartridges were also captured through a real WASAPI output device with a
480-frame buffer at 48 kHz, with device stream gain set to zero. Each probe
continued for 100 callbacks, advanced 24,480 captured frames during the producer
stall, and reported the expected completions/counters. This proves device open
and callback delivery, not an audible listening test or acoustic latency.
For another device, invoke the retained `trace.exe` with arguments
`<game.wasm> <source.luau-or-empty> <capture.f32> 48000 device` and set
`SDL_AUDIODRIVER` for that session. The normal automated suite stays on dummy.

`playerAudio.mixerStatus` exposes the device rate, logical cursor, counters,
scheduling lead and the browser's `baseLatency` / `outputLatency` estimates.
Device latency is separate from the logical lead and includes additional OS,
driver and hardware buffering. Minimum target devices, audible quality checks,
real loopback latency and a universal 50 ms shipping requirement remain open;
synthesis/effects and full-profile publication remain milestones 4d/4e.

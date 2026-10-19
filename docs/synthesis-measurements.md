# Synthesis and effects verification

Run `mise run test:synthesis` on the supported Windows host. It builds matching
Luau/Odin projects twice: an interactive tone cartridge and a full DSP workload.
The retained PNGs, native/web distributions, raw stereo f32 captures, native unit
log and `results.json` live under `build/synthesis-verification/<run>/`.
`mise run test` includes this alongside all existing conformance suites.

The tone cartridge combines wavetable interpolation/morphing, audio-rate FM and
phase modulation, seeded noise, triangle LFO, ADSR, mix/gain/pan, state-variable
filters, sample-rate playback/loops, scheduled partial sample/wavetable edits,
instrument delay and a bus delay/filter chain. It leaves a sustained note running
after the opening phrase; arrows edit pitch/filter and Space morphs its wave.
The browser test drives that editor and checks its changed framebuffer and error
state. Both SDKs must produce byte-identical prepared events and resource data.

Native Wasmtime and the browser-target reference render 48,000 device frames at
44,100, 48,000 and 96,000 Hz, using 127- and 128-frame blocks respectively.
Every PCM sample must match within 1e-6, and both language captures must agree.
The test checks SDK completion decoding, the 2,400-frame silent scheduling lead,
zero late events/stream underruns, and constant linear-memory capacity during
rendering. The normal native player also loads each PNG and must advance its
actual SDL mixer callback.

Independent native unit references check ADSR stage/release boundaries, wave
interpolation/morphing, phase-preserving partial edits, sample interpolation
across loop boundaries, fixed noise vectors, delay impulse echoes and an impulse
filter response against an independent trigonometric coefficient. Those checks
can catch matching mistakes in both hosts: the loop reference caught and fixed
an end-of-buffer interpolation clamp before acceptance. Other fixtures reject
typed-port mismatches, forward/cyclic edges, unstable filter/delay bounds,
missing sources and premature source destruction. The packet corpus mutates
public and prepared graph, resource, scheduling and history descriptors, requires
atomic rollback/recovery, and rejects prepared-event replay.

The full workload uses all 16 voices, eight buses and **320 active nodes**.
Each voice has a wavetable, 13 filters, gain and output. Each bus has eight nodes,
including a filter and delay; this totals 216 simultaneous filters and eight
delays. Shared waveform edits and frequency/cutoff ramps occur during rendering.
A separate native unit workload exercises all slots with a nil allocator during
rendering, then tears down the graphs and requires every audio lease to return.
Queue, snapshot and completion-ring pressure also retain the 4c checks.

SDL capture uses its dummy driver for repeatability. A 500 ms producer stall
occurs while callbacks continue rendering. Actual Chromium AudioWorklet capture
compares the same PCM while the main thread and a worker both stall for 500 ms.
The browser player additionally verifies gesture start, pause/resume epochs and
PNG replacement/reload. SharedArrayBuffer and cross-origin isolation are absent.
The worklet never executes guest code; project DSP renders from prepared bounded
state without allocation, file/network access, compilation or gameplay locks.

Timing fields distinguish native reference elapsed time from
`wasmRenderMs`, which includes the JS render calls and copying their output into
the capture. These are short local runs, not minimum-device guarantees or
speaker latency. Output durations differ with device rate: 48,000 output frames
are one second at 48 kHz but half a second at 96 kHz. Host DSP builds use
production optimization, including when a guest is the small starter cartridge.

The 2026-10-19 local run used Odin dev-2026-10, Luau 0.743, Wasmtime 49.0.3,
Emscripten 6.0.12 and Chromium 156.0.8078.4. Both cartridges had **zero PCM
sample error** across both languages and all three rates, including actual
AudioWorklet capture. Eleven native tests passed; the synthesis corpus rejects
19 malformed public packets and eight prepared packets, then accepts a valid
packet after each failure. The tone fixture delivers four expected completions,
including a queued PCM play cancelled by live-source destruction.
Both fixtures survive the stall and player lifecycle checks.

At 48 kHz, rendering 48,000 device frames gave these short local ranges across
the two cartridge languages:

| Workload | Native reference elapsed | Wasm render calls plus capture copy |
| --- | --- | --- |
| Tone cartridge | 10.4 ms | 15.8–16.3 ms |
| 320 nodes / 216 filters / eight delays | 164–185 ms | 235–248 ms |

Peak retained audio pages were 17,408 bytes for the tone fixture and 45,056 bytes
for stress. The controller reference's linear memory was 28,573,696 bytes and
did not grow while rendering either fixture. These sparse-history fixtures do
not consume the entire arena; the pressure test separately exercises large
declared histories and proves failed note admission leaves an active voice intact.

The portable resource reservation is **55,463,952 bytes**, plus ordinary resource
storage. This includes the expanded producer/renderer metadata, 8 MiB arenas,
prepared command/transfer capacity, feedback credits and scratch. It is a quota
charge, not process RSS. Actual fixture pages, peak live snapshots and Wasm
linear-memory capacity are reported separately. Large declared delay histories
must fit the shared arena when activated; the per-node two-second limit is not
an additional independent allocation allowance.

Device callback capture occurs before OS/hardware output. A muted physical
device probe can establish real driver delivery but cannot prove acoustic
latency, audible quality or the absence of hardware dropouts. Select minimum
devices and perform listening/loopback measurements before turning these
provisional workload and lead targets into shipping guarantees. Full profile
negotiation and publication remain milestone 4e.

Both tone cartridges were also captured through WASAPI at 48 kHz with a
480-frame device buffer and stream gain zero. Each probe delivered 100 callbacks,
advanced 24,480 captured frames during the producer stall, reported four
completions and no late events/stream underruns, and matched the offline PCM
byte-for-byte. This is a real driver/callback probe, not an audible listening test.

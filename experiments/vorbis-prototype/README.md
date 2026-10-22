# Vorbis feasibility prototype

Throwaway experiment on `codex/vorbis-prototype`. It does not change the console,
cartridge format, either SDK, or the existing PCM API.

## Verdict

The follow-up [custom WASM comparison](WASM-COMPARISON.md) resolves the observed
seek/loop failure: compiling libvorbisfile with Emscripten provides the same
`ov_pcm_seek` operation used by native, with gap-free playback and no PCM loop
cache on the tested fixture. Prefer this direction for the next integration
slice, while keeping mobile playback and overall browser memory unqualified.

The original package-only findings below are retained as baseline evidence.

Native libvorbis is a promising decoder. The browser package produces matching
PCM and supports incremental playback, but its current reset-and-discard approach
does not provide reliable arbitrary music loops. Keep the library choice
provisional until seeking, memory bounds and mobile playback are qualified.

A short decoded loop cache removes the observed gaps, at the cost of PCM memory.
That is useful for short loops, but is not a solution for looping entire music
tracks. Moving the complete producer into a worker and implementing seek/preroll
are the next experiments before adopting this approach.

## Run

Requires the repository toolchain, Windows x64 with Visual Studio C build tools,
an audio output device, and FFmpeg with libvorbis encoding. Run from the root:

```sh
mise exec -- npm ci
mise exec -- npm ci --prefix experiments/vorbis-prototype
mise run //experiments/vorbis-prototype:measure
mise run //experiments/vorbis-prototype:compare
mise run //experiments/vorbis-prototype:serve
```

The interactive page is at `http://127.0.0.1:8094/`. Use one playback button at a
time. The measurement task builds dependencies and fixtures, exercises native
output and Chromium AudioWorklet playback, and writes `report.json`, PCM captures,
dependency provenance and a screenshot under ignored `build/vorbis-prototype/`.
Negative playback scenarios are measured results, not harness errors; inspect
the individual verdict fields. `parityPassed` deliberately includes the failing
uncached loop case. The build downloads hash-checked official Xiph source archives.

Pinned candidates: `@wasm-audio-decoders/ogg-vorbis` 0.1.20, libvorbis 1.3.7 and
libogg 1.3.5. The custom WASM build uses the repository's Emscripten 6.0.12.
No downloaded libraries or generated audio are tracked.

## What is measured

- Deterministic synthetic 180-second stereo 48 kHz music and eight-second mono
  44.1 kHz audio, encoded using FFmpeg libvorbis quality 4. Music occupies about
  1.25 MB compressed versus 69.12 MB decoded float PCM. These are fixtures, not a
  representative compression-quality study of commercial music.
- Browser worker decoding in 4,096-byte compressed chunks; native libvorbisfile
  decoding into 1,024-frame chunks. The browser package can return a full second
  of PCM at once, so decoded output is sliced before entering the queue.
- Full-file PCM compared between hosts and against FFmpeg's independent Vorbis
  decoder, with equal sample counts, finite values and maximum error below
  0.00002. Loop output is also compared against a slice of full-file decoding.
- Sample-index loop from frame 7,212,000 to 7,332,000 exclusive (150.25–152.75 s),
  repeated four times. Native uses `ov_pcm_seek`; the browser resets and decodes
  from the beginning because the package exposes no seek method. Loop points
  intentionally need not be zero crossings; matching their discontinuity is
  correct sample sequencing, not a promise of click-free arbitrary loop points.
- Eight seconds of real-time browser AudioWorklet output, with 8,192- and
  32,768-frame queues, starvation counters and rendered PCM capture. Additional
  scenarios stall the producer's main thread for 250 ms or one second.
- Native incremental decoding and looping into four WinMM output buffers, with
  submitted PCM captured and compared. This verifies submitted samples and
  successful device consumption; it does not measure device underruns or record
  sound from the physical output.
- Native process private memory before/during/after decoding and 128 open/read/
  close cycles. Browser main-thread heap samples, 24 decoder resets, forced
  main-thread GC, and whole-browser process private-memory samples.

## Observations

See [results.json](results.json) for the retained run's exact measurements.

| Scenario                                    | Observed result                                                              |
| ------------------------------------------- | ---------------------------------------------------------------------------- |
| Full decode, stereo and mono                | All sample counts match; maximum host/reference error below 0.00000025       |
| Straight browser streaming, either queue    | No underruns or queue overflows; rendered PCM matches native                 |
| Native sample-index seek and loop           | Exact match to reference slice; four seeks take roughly 1 ms total           |
| Browser reset/discard looping, larger queue | Audible-time gaps measured as inserted silence; fails rendered parity        |
| Cached 2.5-second loop, console-sized queue | No gaps; rendered PCM matches; cache costs 960,000 bytes                     |
| 250 ms producer stall, console-sized queue  | Underruns, as expected with only 171 ms total queue capacity                 |
| 250 ms producer stall, larger queue         | No underruns in this run                                                     |
| One-second stall, larger queue              | Underruns; recovery resumes queued samples rather than advancing source time |

Browser reset/discard seeks to the late loop take roughly 0.7–0.8 seconds here.
The larger ring has 683 ms capacity but is deliberately not kept completely full;
it cannot mask this delay. Re-decoding from the start also scales with loop offset.
The cache experiment proves correct wrapping without repeated seeking, but its
memory grows with loop duration (384,000 bytes per stereo second at 48 kHz).

Native private memory is small in this probe (roughly 1–1.5 MB, including the
executable and allocator retention). Browser memory is substantially noisier and
larger. The worklet rings themselves cost only 65,536 or 262,144 bytes; measurement
capture adds 3,072,000 bytes per playback. Compressed input is held resident, as
it would be in an already-loaded cartridge blob. Decoder output, parser state,
worker/WASM memory and transferred messages are additional costs.

Browser `performance.memory` excludes the decoder worker and its WASM heap.
Whole-browser private memory includes Chromium, audio infrastructure, capture
and test overhead; it cannot be charged directly to the decoder. Reset stress
shows allocation churn and some retained process memory after GC, but does not
by itself prove a leak or a stable upper bound. A production decision needs
worker/WASM allocation instrumentation and a longer plateau test.

## Integration decision still open

The existing mixer has a fixed resource budget; neither these process totals nor
a bounded output ring proves the decoder fits it. Compressed blobs, decoder
state, outstanding decoded pages, PCM queues and optional caches need separate
limits and accounting. Vorbis should feed the same PCM mixer path on both hosts;
cartridge APIs should remain independent of the decoder implementation.

The worker variant decodes off-thread, but Ogg parsing and the producer loop in
this prototype still run on the main thread. Test moving the entire producer
there, bounded transfers/backpressure, and sample-accurate seek with preroll or a
decoder interface that already supports it. Explicitly choose starvation
semantics, loop metadata, source-rate conversion, and stop/restart ownership.

This probe uses Windows WinMM and desktop Chromium, not the actual Odin/SDL
console mixer. It does not qualify Safari, Firefox, mobile devices, 44.1 kHz
resampling during playback, concurrent voices, malformed/chained media, network
streaming, suspension/resume, snapshots, cartridge reload, or long-run memory
bounds. Full music is incrementally decoded; real-time playback windows are
eight seconds each. Do not interpret that as a full-length playback soak test.

## Sources

- [Browser decoder implementation and API](https://github.com/eshaz/wasm-audio-decoders/tree/master/src/ogg-vorbis)
- [Xiph libvorbisfile API](https://xiph.org/vorbis/doc/vorbisfile/)
- [Sample-index seeking](https://xiph.org/vorbis/doc/vorbisfile/ov_pcm_seek.html)
- [Official source downloads](https://downloads.xiph.org/releases/vorbis/)

# Shared libvorbisfile seeking: WASM comparison

## Decision

Compiling libvorbisfile ourselves is a better candidate for native/browser music
parity than the package's reset-and-discard path. The prototype uses the same
`ov_pcm_seek` and `ov_read_float` operations as native, and successfully loops
without a decoded PCM cache. This supports proceeding to a small console
integration; it does not establish production readiness or mobile support.

Run `mise run //experiments/vorbis-prototype:compare` from the repository root.
The task builds both native and WASM code and records `comparison.json` and PCM
captures in `build/vorbis-prototype/`. The retained run is
[comparison-results.json](comparison-results.json). The interactive page has a
libvorbisfile WASM loop button (`mise run //experiments/vorbis-prototype:serve`).

## Implementation

Emscripten 6.0.12 compiles the pinned libogg 1.3.5/libvorbis 1.3.7 sources with
`-O3`, a fixed 8 MiB linear memory, and no filesystem. The generated WASM binary
is 176,792 bytes (uncompressed). `wasm.c` supplies bounded reads and byte seeks
over one resident compressed buffer to `ov_open_callbacks`. The worker opens,
seeks, reads at most 1,024 PCM frames per request, and closes the decoder. It
transfers PCM to the main-thread producer, which feeds the existing probe's
AudioWorklet queue. Library callbacks, parsing and decoding all run in the worker.

One worker owns one decoder. Closing clears libvorbisfile before freeing the
compressed buffer; freeing the client terminates its worker. A separate stress
case keeps the module alive for 128 open/seek/read/close cycles to check that
termination is not hiding retained native allocations. The bridge is a probe,
not a public SDK API or an Odin binding.

The first attempted build opened with a null callback data-source pointer;
libvorbisfile treats that as unavailable input. The measured build passes the
resident source pointer. The failing attempt is excluded from the retained run.

## Results

Both candidates run in fresh desktop Chromium processes with the same fixtures,
8,192-frame stereo queue, eight-second rendered PCM capture and comparison
tolerance of 0.00002. Both decode the complete 180-second stereo track, repeat a
late-track loop four times, and decode the mono fixture once and then 24 times.
The package additionally exercises its PCM-cache workaround; custom WASM also
has the 128-cycle lifecycle check. Timings are observations, not portable limits.

| Measurement                        | Package 0.1.20                            | Custom libvorbisfile WASM                             |
| ---------------------------------- | ----------------------------------------- | ----------------------------------------------------- |
| Ordinary streamed playback         | No underruns                              | No underruns                                          |
| Late-track loop without cache      | 89,344 silent frames (1.86 s in 8 s)      | No underruns                                          |
| Late-track loop setup              | 954–1,098 ms, reset and decode from start | 0.5–3.8 ms including worker round trip and first read |
| Actual `ov_pcm_seek` call          | Not exposed                               | 0.1–2.9 ms                                            |
| PCM loop cache                     | 960,000 bytes removes gaps                | Not needed                                            |
| Full decode and loop sample parity | Pass                                      | Pass                                                  |
| Rendered loop parity, no cache     | Fail                                      | Pass                                                  |
| 250 ms main-thread producer stall  | 5,888 silent frames                       | 5,696 silent frames                                   |

All successful decode comparisons have equal sample counts and maximum absolute
error below 0.00000025 against native output. The full-file native baseline was
also checked against FFmpeg's independent decoder in the original experiment.
Loop points are frame 7,212,000 to 7,332,000 exclusive, deliberately not chosen
as zero crossings; parity tests correct sample sequencing, not arbitrary click
removal. The playback probe's `startupMs` starts after decoder initialization;
do not interpret it as cold page-to-audio latency.

## Memory

The custom module's fixed linear memory stayed at **8,388,608 bytes**. Sampled
`mallinfo().uordblks` reached **1,423,448 bytes**, including the **1,249,816-byte**
compressed track. That leaves about 174 KB of sampled live decoder/allocator
allocations beyond input. Static data, stack and free allocator space are part
of the 8 MiB capacity but not that live-allocation count. Sampling after API calls
can miss transient allocations inside a call; the fixed capacity still bounds
the module's entire linear memory for these successful runs.

After every one of 128 open/seek/read/close cycles, live allocator usage returned
to its initial value of **zero**. That is evidence of clean ownership for this
fixture and lifecycle, not proof about every malformed file or decoder path.

| Whole-browser private memory             | Package   | Custom WASM |
| ---------------------------------------- | --------- | ----------- |
| Initial                                  | 80.7 MiB  | 78.2 MiB    |
| Sampled maximum                          | 507.6 MiB | 365.0 MiB   |
| After freeing workers and main-thread GC | 293.0 MiB | 325.9 MiB   |

These totals include Chromium, audio devices, JavaScript allocation churn,
compressed-input copies, transferred PCM and capture overhead. Sampling is once
per second, and scenario mixes include the additional cases described above.
The custom run has a lower observed peak but a higher retained total; **we cannot
claim universally lower browser memory** from this experiment. Main-thread
`performance.memory` does not include worker/WASM heaps. The package's internal
allocator is not instrumented here, so no direct per-decoder allocator comparison
is claimed. The custom module's fixed heap and ownership measurements are the
stronger evidence for predictable budgeting.

The output ring costs 65,536 bytes and capture costs 3,072,000 bytes, outside the
WASM heap. Main-thread compressed input and worker message copies are outside it
too. An 8 MiB decoder module cannot accommodate every possible cartridge blob;
the limit is a deliberate probe setting, not a proposed cartridge constraint.

## Remaining integration work

- Move refill scheduling/transport off the main thread or otherwise provide
  adequate prebuffering. Both candidates still starve under a 250 ms producer
  stall; improving seek does not fix that.
- Integrate one native/browser stream lifecycle through the Odin mixer and both
  cartridge SDKs, with explicit ownership and budget accounting for compressed
  data, decoder heaps, in-flight PCM and queues.
- Qualify mobile/Safari/Firefox, source-rate conversion, stop/restart and suspend,
  malformed/chained inputs, more than one stream, and long-running playback.
  Current real-time windows are eight seconds; full tracks are decoded offline.
- Measure worker JavaScript and end-to-end process memory under the final
  transport design. Avoid allocating a separate 8 MiB module per stream without
  evaluating a shared decoder arena or other budget strategy.

The API choice follows Xiph's documented
[memory-backed callbacks](https://xiph.org/vorbis/doc/vorbisfile/ov_open_callbacks.html)
and [sample-accurate seeking](https://xiph.org/vorbis/doc/vorbisfile/ov_pcm_seek.html).
No production runtime, cartridge format or SDK changes are included.

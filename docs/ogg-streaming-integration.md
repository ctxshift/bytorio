# Ogg streaming integration

The selected decoder is libvorbisfile on native and our own build of the same
library for browser WASM. The package comparison remains under
`experiments/vorbis-prototype/` as evidence.

The first integration slice uses SDK 0.7.0, the explicit experimental profile
`ogg-streaming-preview-1` (ID 7, resource protocol 9), and immutable
cartridge content IDs. `audio.ogg_stream(content_id, options)` returns a normal
stream handle in both SDKs. Existing stream playback, buses, gain, pan, stop and
destruction remain the mixer interface. PCM uploads to an Ogg-owned stream are
rejected. Loop endpoints are source-frame indices with an exclusive end.

Initial media scope is single-link mono/stereo Vorbis at 48 kHz; other sample
rates are rejected until shared source-rate conversion is implemented. Playback
follows the existing stream clock: creation anchors frame zero at the creation
tick, voices can attach independently, and stopping a voice does not rewind its
stream. Destroy the stream to release its decoder. Nonlooping streams end their
voices naturally at EOF. Looping starts at source zero and wraps at loop end.

The runtime owns stream timing, queue bounds, loop position and generation checks.
Host adapters own decoding and feed bounded PCM through that runtime contract.
Browser decoding/refill runs on the game Worker and talks directly to the AudioWorklet
through a MessagePort. Main-thread telemetry cannot control progress. Native
decoding stays out of the SDL callback; the initial native adapter services the
producer from the host loop. Dedicated native background scheduling is a later
integration step if host-loop starvation measurements require it.

The browser lazily creates a fixed 8 MiB decoder memory when an Ogg stream first
exists. The resource budget reserves that amount until session close. Compressed
input is copied into decoder ownership, with a 2 MiB per-stream and 4 MiB aggregate
limit. Native uses the same source limits and accounting reservation, but its
libvorbis allocations still use the C allocator: the reservation is not a hard
native allocator cap. Enforcing that cap is a remaining integration requirement.

Refill decodes at most 1,024 source frames per operation and maintains the existing
8,192-frame stream window. It seeks with `ov_pcm_seek` at loop boundaries.
Loops of at most 1,024 frames use one bounded cached period inside the decoder,
so even a one-frame loop fills normal chunks without excessive seeks. If a
producer misses its queue deadline, the runtime skips elapsed source frames and
resumes after the scheduling lead; it does not silently replay stale music.
Worker game code can still starve its own refill timer. Native host-loop stalls
and browser Worker stalls therefore remain distinct from UI-thread isolation.

Container bounds and supported identification fields are checked transactionally
before publication. Full codec setup runs when the host opens the decoder;
corrupt codec setup fails the player session. This is a streaming PCM decoder
over resident cartridge bytes, not HTTP range or network streaming.

`mise run deps:vorbis` builds pinned libogg 1.3.5 and libvorbis 1.3.7 from
hash-verified upstream archives. `mise run test:ogg` checks both SDK/host paths,
an independent FFmpeg reference, irregular loop boundaries, EOF, resource
rollback, stale handles, rejection of manual writes and unsupported media,
browser UI stalls, pause/resume and reload. Retained results are written to
`build/ogg-verification/report.json`. The longer streaming/memory comparison
remains in the prototype; this integration has not qualified mobile devices.

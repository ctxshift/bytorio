# Use libvorbisfile on native and browser hosts

Use native libvorbisfile and a project-built WebAssembly version of the same
decoder for Ogg Vorbis, feeding both into the existing PCM stream mixer.
Its sample-accurate seeking supports arbitrary loop boundaries without retaining
an entire decoded music track or replaying decoding from the beginning on each
loop.
Maintain the decoder build and bridge in exchange for consistent seeking
semantics across hosts; this choice does not make the experimental Ogg profile
a stable or universally qualified capability.

Supported media and memory limits: [Ogg streaming](../ogg-streaming-integration.md).

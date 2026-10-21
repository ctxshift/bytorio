# Synthesis and effects: resource-av-1

Luau and Odin now author the same typed DSP graphs, evaluated by the shared Odin
mixer on native and browser using **resource protocol 4**, published as
SDK 0.2.0 / ABI 2 / `resource-av-1`. Players retain protocols 1–3 through the
compatibility adapter. See [profile conformance](../docs/resource-profile.md).
The [PCM audio reference](audio.md) defines clocks, voices, routing, queues,
feedback, pause and device delivery shared by this API.

## Build an instrument

An instrument is an immutable array of nodes. Node indices are **zero-based**
in both languages, including inside ordinary one-based Luau arrays. Each input
must refer to a preceding node; the final node must be `output`. This makes graph
order explicit and rejects forward references and cycles. Only a delay node's
own bounded history permits feedback. Definitions share source storage; each
playing voice owns its phase, random generator, envelopes, filters and history.

```luau
local instrument = audio.instrument({
    { kind = "noise", seed = 1234567 },
    { kind = "adsr", attack_frames = 48, decay_frames = 480,
        sustain = 0.3, release_frames = 2400 },
    { kind = "gain", input = 0, gain = 0, gain_input = 1, depth = 0.15 },
    { kind = "filter", input = 2, cutoff_hz = 2000, resonance = 0.2 },
    { kind = "output", input = 3 },
})
local voice = audio.voice(0)
audio.note_on(voice, instrument, 440, { velocity = 0.8 })
audio.note_off(voice, audio.time() + 48000)
```

```odin
instrument := audio.instrument([]audio.Node {
    {kind = .Noise, seed = 1234567},
    {kind = .ADSR, attack_frames = 48, decay_frames = 480,
        sustain = 0.3, release_frames = 2400},
    {kind = .Gain, input = 0, gain = 0, gain_input = 1, depth = 0.15},
    {kind = .Filter, input = 2, cutoff_hz = 2000, resonance = 0.2},
    {kind = .Output, input = 3},
})
voice := audio.voice(0)
audio.note_on(voice, instrument, 440, {velocity = 0.8})
audio.note_off(voice, audio.time() + 48000)
```

`note_on(voice, instrument, frequency_hz, opts)` uses an explicit frequency in
Hz, 1–20,000. It is a pitch multiplier relative to 440 Hz for all sample and
wavetable nodes: a wavetable declared at 440 Hz plays at the note frequency;
one declared at 110 Hz plays two octaves lower. It does not transpose LFOs.
Options are `at`, `bus`, `velocity` [0,1] (default 1) and `pan` [-1,1] (default 0).
Starting a note resets that voice's state. A later `note_off` starts all ADSR
release stages and completes the voice when they finish. Without an ADSR it
stops immediately. Instruments are explicitly gated, including sample-only
instruments; exhaustion of a sample node produces silence until the note ends.
Existing `stop`, explicit fade `release`, voice gain and pan also work on notes.

## Node descriptors and ports

Luau exports `byt.SynthNode` with a string `kind`. Odin uses `audio.Node`
and `audio.Node_Kind`. Omitted input fields mean disconnected; **zero is node
zero**, not a disconnected input. Odin represents optional indices, sources and
defaulted scalars with unions, preserving explicit zero. Resource handles remain
opaque/distinct `Sample`, `Wavetable`, `Instrument` and `Bus` types.

| Luau kind / Odin kind | Inputs and options | Output |
| --- | --- | --- |
| `input` / `.Input` | Bus effects only; current mixed bus input | Stereo audio |
| `sample` / `.Sample` | `source: Sample`, `rate` default 1, `loop`, `loop_start`, exclusive `loop_end` | Mono/stereo audio |
| `wavetable` / `.Wavetable` | `source: Wavetable`, `frequency_hz` default 440, `wave` default 0, `phase_cycles` default 0 | Mono audio |
| `noise` / `.Noise` | `seed` nonzero u32, default 1; independent xorshift32 state per instance | Mono audio |
| `constant` / `.Constant` | `value` [-16,16], default 0 | Scalar control |
| `mix` / `.Mix` | Audio `input`, audio `other`; weights `gain`, `secondary_gain`, both default 1 | Audio, stereo if either input is stereo |
| `gain` / `.Gain` | Audio `input`; `gain` default 1; optional mono/control `gain_input`, `depth` default 1 | Same audio type as input |
| `adsr` / `.ADSR` | `attack_frames`, `decay_frames`, `release_frames` default 0; `sustain` default 1 | Scalar control |
| `lfo` / `.LFO` | Triangle, `frequency_hz` [0,200], default 5; `phase_cycles` default 0 | Scalar control |
| `filter` / `.Filter` | Audio `input`; `cutoff_hz` [20,20000], default 1000; `resonance` [0,0.95], default 0 | Same audio type as input |
| `delay` / `.Delay` | Audio `input`; required `max_delay_frames`; `delay_frames` defaults to maximum; `feedback` [-0.95,0.95] default 0, `wet` [0,1] default 0.5 | Same audio type as input |
| `pan` / `.Pan` | Audio `input`, `pan` [-1,1], default 0; linear balance | Stereo audio |
| `output` / `.Output` | Audio `input`; final node | Stereo audio |

Mono is duplicated when mixed with stereo. Control signals cannot be wired into
an ordinary audio input or output. `frequency_input` and `phase_input` on
wavetable nodes, and `gain_input` on gain nodes, accept **mono audio or scalar
control**, evaluated every logical frame. Stereo modulation is rejected.

Wavetable modulation uses `frequency_hz * note_pitch + frequency_input *
fm_depth_hz` and `accumulated_phase + phase_cycles + phase_input *
pm_depth_cycles`. Frequency is clamped to [-24,000,24,000] Hz after modulation;
negative frequency runs backwards. Depth bounds are ±24,000 Hz and ±16 cycles.
The phase accumulator wraps in cycles and continues across controls/source edits.
Gain modulation is `input * (gain + gain_input * depth)`; the resulting multiplier
is clamped to [-16,16]. A zero base gain plus an ADSR input applies the envelope.

Each node output clamps to [-16,16] before downstream processing; master output
retains the PCM mixer clamp [-1,1]. Sample playback uses linear source-rate
interpolation. Waveforms interpolate linearly within a cycle and between adjacent
wave indices. Noise maps its next u32 to `word / 2^31 - 1`. Triangle LFO output is
`1 - 4*abs(wrapped_phase - 0.5)`, starting at -1 at phase zero.

Filter modes are `"lowpass"`, `"bandpass"`, `"highpass"` in Luau and
`.Lowpass`, `.Bandpass`, `.Highpass` in Odin, default lowpass. The shared
state-variable filter uses two integrators/channel, damping `2 - 1.9*resonance`
and a fixed rational coefficient (defined in the reference DSP) to avoid platform
libm differences. Very small integrator values are cleared below 1e-20.
Delay history is stereo, tap lengths are floored to whole frames, and feedback
writes clamp to [-16,16]. Changing a tap changes its read position immediately;
there is no hidden crossfade. Wet output is `dry*(1-wet) + delayed*wet`.

ADSR ramps use the current value on the event frame, then advance toward their
target. Attack reaches 1, decay reaches sustain, sustain follows its parameter,
and note-off releases from the current level to zero. Zero-length stages advance
immediately. The decay target and attack/decay/release lengths are read on stage entry;
changing a length does not restart a stage already running. ADSR frame durations
are floored when their stage starts. Release truncates
instrument-local effect tails when the voice completes; put effects on a bus
when their tails should continue after a note.

## Mutable sources and controls

`audio.wavetable({frames=32, waves=2}, pcm)` creates mono f32 storage: 32–2,048
frames per cycle, power of two, 1–64 waves, consecutive in the buffer. Odin uses
`audio.Wavetable_Desc`. `pcm.frames` must equal `frames*waves`; values must be
finite in [-1,1]. Both SDKs destroy these resources with `destroy_wavetable` and
`destroy_instrument`.

`edit_sample(sample, first, pcm, at)` and `edit_wavetable(table, first, pcm, at)`
copy a partial replacement into SDK staging immediately, then apply it at the
scheduled logical frame. `first` is a source-frame offset; wave-table offsets
span the flattened sequence of waves. Channel counts must match. Existing voices
and future notes observe the changed source at that frame without phase or
position reset. Equal-frame edits/notes execute in accepted command order.
Accepted edit buffers can be reused immediately; queued patches retain their
own storage until consumed.

A sample becomes a live shared synthesis source when first used by an instrument
or explicitly edited. Its initial contents are captured then. Subsequent updates
must use `edit_sample`; ordinary unscheduled `audio.write` is rejected for a live
source. PCM-only samples keep the 4c snapshot-at-play behavior until explicitly
made live. Active PCM voices adopt the live source on an edit while preserving
position. Instrument/effects definitions retain their source handles: destroy
dependent definitions or clear effects before destroying a source. Destroying an
instrument cancels its active/future notes. Source destruction cancels remaining
PCM voices, pending edits and future PCM plays submitted after that source
became live. Plays accepted before live binding retain their original fallback
snapshot if the live source subsequently disappears.

`node_control(voice, instrument, node, parameter, value, at, ramp_frames)` targets
a node in that instrument instance; controls for a replaced voice using a
different instrument are ignored. `effect_control(bus, node, parameter, value,
at, ramp_frames)` targets the bus's current chain. The host rejects parameters
for the wrong node kind, invalid ranges, and wave indices outside the table.
Ramps share the PCM timing rules. Node indices are zero-based.

| Parameter string / Odin enum | Valid nodes |
| --- | --- |
| `frequency` / `.Frequency`, `phase` / `.Phase` | Wavetable, LFO |
| `wave` / `.Wave` | Wavetable |
| `rate` / `.Rate` | Sample |
| `gain` / `.Gain` | Gain, mix, constant |
| `secondary_gain` / `.Secondary_Gain` | Mix |
| `depth` / `.Depth` | Gain modulation or wavetable FM depth |
| `pan` / `.Pan` | Pan |
| `cutoff` / `.Cutoff`, `resonance` / `.Resonance` | Filter |
| `delay_frames` / `.Delay_Frames`, `feedback` / `.Feedback`, `wet` / `.Wet` | Delay |
| `attack` / `.Attack`, `decay` / `.Decay`, `sustain` / `.Sustain`, `release` / `.Release` | ADSR |

## Bus effects and bounds

`effects(bus, nodes, at)` replaces a bus's complete chain; an empty array/slice
clears it. The graph may use `input` and cannot use ADSR. Topology replacement
must use the **current simulation frame** (omit `at` or pass `audio.time()`).
Future parameter changes still use absolute scheduling. Replacement resets the
chain's history; parameter controls retain it. Child buses render before parents,
with each chain applied before its bus gain. Master effects are supported too.

There are at most 64 immutable instrument definitions, 16 nodes/instrument,
eight nodes/bus and 320 active nodes across all voices and buses. A delay may
declare at most 96,000 frames (two seconds) of history. All live source PCM,
definitions, patches, note history and retired leases share the bounded **8 MiB
audio arena**. Creation validates graph history; starting a note/chain reserves
and clears all its history on the producer. Arena exhaustion fails the entire
commit; there is no callback allocation or hidden eviction. A declared maximum
per node does not grant every node that much storage simultaneously.

Protocol 4 expands the fixed portable audio reservation to **55,463,952 bytes**
on both hosts for metadata, PCM arenas, command/transfer/feedback storage and
scratch. Ordinary resource storage is charged additionally within the 64 MiB
quota. No arbitrary guest DSP callbacks, topology feedback or host-device access
is exposed. [Profile negotiation](../docs/resource-profile.md) is published;
minimum hardware and physical device latency remain unqualified.

The matching [Luau tone cartridge](../tests/synthesis/cartridges/game.luau) and
[Odin tone cartridge](../tests/synthesis/cartridges/game.odin) demonstrate the
interface. After the opening phrase, arrows change pitch/filter and Space morphs
the sustained waveform. The [stress cartridge](../tests/synthesis/stress/game.luau)
uses all voice/bus/node slots with live edits and ramps. Run `mise run test:synthesis`
to build both and retain playable PNG/native/web exports under
`build/synthesis-verification/<run>/`. See [verification](../docs/synthesis-measurements.md).

# Text input

Text entry uses the operating system's committed Unicode input. Declare a single
field before displaying its screen, keep the last returned value, and close the
field when leaving that screen. This optional host service works with existing
profiles; cartridges that do not use it retain their input behavior.

Luau exposes `byt.text_input.configure(options)`, `byt.text_input.read()` and
`byt.text_input.close()`. Odin imports `text "sdk:text"` and provides the same
operations. `configure` returns a boolean and takes `id`, `value`, `max_bytes`,
`x`, `y`, `width`, `height`, `selection_start` and `selection_end`. The ID must be
nonzero. Coordinates use the game's logical canvas. Selection offsets count
UTF-8 bytes; Luau defaults both offsets to the end, while Odin sets them explicitly.

Call `configure` when opening or programmatically changing the field. Calling it
every tick discards host edits and restarts the session. Values are valid UTF-8,
single line, at most 256 bytes, with a field-specific cap from 1 to 256 bytes.
ASCII control characters are rejected. Selection endpoints must be ordered and
lie on UTF-8 boundaries. An oversized edit is rejected in full.

`read` returns the latest committed value and selection, plus `changed`,
`submitted` and `cancelled`. The snapshot is available once per update tick;
event flags drain on that successful read and are false on subsequent ticks.
Multiple host edits between ticks coalesce into the latest bounded snapshot.
An insufficient destination leaves the snapshot pending. Odin takes a caller
buffer of at least `text.MAX_BYTES` and returns `(Event, bool)`; `Event.value`
borrows that buffer until its next use. Luau returns an event table or `nil`.

IME preedit stays with the operating system and never becomes committed game
text. Backspace edits the selection or preceding Unicode code point on native;
the browser uses its platform editor. Enter submits and Escape cancels, except
while an IME composition is active. Both deactivate the host editor while
retaining the final value for reads. Cancellation reports the current committed
value; restoring the original value is the game's decision. `close` discards all
pending state. Games own their character filtering and final acceptance rules.
Native editing also supports Left/Right, Home/End, Shift selection, Delete,
Ctrl+A and Ctrl+C/X/V. Selection moves by Unicode code point. Pasting a value
that exceeds the field's byte limit leaves both value and selection unchanged.

On native, SDL text input starts when the field is configured, and keyboard
game controls are suppressed while editing. Pointer controls remain available.
Losing window focus cancels native editing and retains the committed value.
On browser, a real DOM input overlays the declared field so its focus occurs
synchronously inside the trusted pointer gesture. Declare the field before the
tap: a worker response after a tap cannot reliably summon a phone keyboard.
Composition, selection and clipboard behavior remain browser-owned. A focused
field blocks game keyboard controls. Replacing or unloading the game, or a
player failure, closes the field. Browser tab or window blur preserves the
configured field and committed value.

The host imports are `text_configure(pointer, length) -> u32` and
`text_read(pointer, capacity) -> u32`. Both use a fixed 48-byte little-endian
header followed by up to 256 UTF-8 bytes. The authoritative layout and flag
values live in `contract.json` under `textInput`. Configure takes revision zero;
the host assigns a fresh nonzero revision to each accepted configuration and
close. Browser edits carry that revision and a monotonically increasing sequence
to reject events from an earlier field or a repeated delivery. Validation failure
returns zero without changing the prior state or touching an output buffer.

Run `mise run validate test:text-input` for SDK lifecycle, native SDL event,
UTF-8 boundary and browser editing coverage.

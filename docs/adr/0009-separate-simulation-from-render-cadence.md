# Keep simulation independent of render cadence

Advance simulation at a fixed 60 Hz while treating render cadence as a host
preference, so display speed does not change gameplay speed.
Advance game state and consume input edges during updates; submit resource
changes and scheduled audio at initialization or update boundaries so repeated
draws do not repeat those effects.
Bound catch-up work and reset the scheduling clock after suspension rather than
replaying an unbounded backlog; fixed ticks alone do not guarantee deterministic
cross-platform replay or interpolated movement.

Timing rules: [frame pacing](../frame-pacing.md).

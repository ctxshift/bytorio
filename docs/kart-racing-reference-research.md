# Kart-racing reference and design targets

Research date: 2026-10-21. This note uses Nintendo's published material to identify
the controls and feedback that make **Mario Kart DS** a useful racing reference.
The Bytorio baseline uses an original course, vehicles and HUD, with the existing
player sound cue for event feedback.
It does not reproduce proprietary code, assets or an exact physics model.

## What the primary sources establish

The [official instruction booklet, pages 6–9](https://www.nintendo.com/eu/media/downloads/games_8/emanuals/nintendo_ds_21/Manual_NintendoDS_MarioKartDS_EN.pdf)
documents separate acceleration and braking/reverse, steering, a hop/drift input,
item use and pause. A drift starts while accelerating and steering; alternating
steering during the drift produces sparks, and releasing drift activates a short
mini-turbo. Correctly timed acceleration during the countdown gives a launch
boost. These are deliberate player actions, rather than an automatic bonus for
holding a corner.

The same booklet, pages 10–15 and 22, describes random pickups, eight competing
karts, current item, position, lap count, elapsed time, a course map and pause/
restart. Its race-screen illustrations place the vehicle behind the road ahead,
with the race view separated from supplementary information. The manual does
not publish collision formulas, drift coefficients, camera filtering, polygon
counts or texture budgets. [Nintendo's product overview](https://www.nintendo.com/en-gb/Games/Nintendo-DS/Mario-Kart-DS-271518.html)
confirms the broader emphasis on varied courses, items and multiple race modes;
recreating that entire feature set is outside this baseline.

## Proposed Bytorio baseline

The following are **original implementation targets**, not measured constants
from the reference. Tune them through playtesting in both SDKs.

| Area           | Concrete target                                                                                                                                                                                                                                                                     |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Race loop      | One original closed course, three laps, a countdown, a finish state and one-action restart. Opponents share the course; rank comes from validated course progress, not a scripted timer.                                                                                            |
| Steering       | Accelerate, brake/reverse and steer independently. Speed affects turning. Separate kart facing from travel direction so a drift visibly slides instead of rotating the whole world.                                                                                                 |
| Drift          | Hop on entry, lock the initial drift direction, allow countersteering, show charge/sparks, and grant a brief boost only on a charged release. A simple charge timer is a useful first approximation but should be identified as a simplification.                                   |
| Track response | Grass visibly slows the kart, barriers prevent leaving the course, collisions briefly reduce speed, and ordered checkpoints prevent shortcut lap counting. Returning to the road should feel forgiving.                                                                             |
| Camera         | Perspective chase view with a low-center kart, road look-ahead and damped position/heading. Start around a 55–65 degree vertical field of view, then tune for road readability. Camera lag must not obscure the inside of a turn.                                                   |
| Course         | Broad bends plus one tighter sequence, elevation changes, bright verge markings, landmarks and a readable start/finish gantry. Geometry occupies real world space with depth-tested vehicles and trackside objects.                                                                 |
| Visual style   | Favor chunky vehicle silhouettes, small crisp textures, saturated region colors, simple directional shading, an uncluttered sky and soft distance fog. Avoid fine texture noise that flickers at 320×180. Wheels, driver and chassis should read as a vehicle at gameplay distance. |
| HUD            | Adapt to one 320×180 screen: item/status in a small upper corner, lap/time opposite, prominent position near a lower corner, compact minimap elsewhere. Preserve the road horizon and steering sightline. Use original flat panels, icons and typography.                           |
| Feedback       | Distinct countdown tones, engine pitch tied to speed, drift/spark cues, a boost cue, impact feedback and a finish announcement. Driving state must be legible without opening diagnostics.                                                                                          |
| Pickups        | An original boost pickup is sufficient to exercise collection, cooldown, inventory and activation. It does not constitute the full randomized attack/defense system.                                                                                                                |

## Acceptance and tuning

These targets guide the direction rather than promise every feature in the first
baseline. [The implemented baseline](kart-racing.md) documents its simpler AI,
road-relative handling, vertex-colored models, and current audio limits.

- Use the same simulation constants, initial conditions and replay controls in
  Luau and Odin. Compare lap/rank/drift/boost states independently of image hashes.
- Exercise countdown, standing start, braking, both steering directions,
  countersteer/release, off-road recovery, lap completion and restart. Include
  moving opponents and camera motion in performance captures.
- Keep CPU rendering the default. GPU rendering, resident meshes and SSAA remain
  optional quality/performance settings. The game rules must be identical.
- Build static course resources once; update vehicle transforms and camera state
  during play. Report startup separately from steady-state frame timings, and
  distinguish CPU submission time from GPU completion and display delivery.
- Judge the baseline by predictable control, readable corners, useful feedback
  and repeatable laps. Exact commercial-game feel needs subsequent hands-on
  tuning; documentation alone cannot establish it.

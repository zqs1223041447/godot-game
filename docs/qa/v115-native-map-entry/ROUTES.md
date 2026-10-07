# Bounded native study route detours

`scripts/studies/modular_study_routes.gd` exposes:

`static func prepare(original_landmarks: Dictionary, geometry: RefCounted) -> Dictionary`

The exact receipt keys are `ok`, `reason`, and `landmarks`. A success contains a
deeply detached copy of every supplied landmark field, with only
`route_segments` replaced. Failure contains a nonempty reason and empty
landmarks. The helper requires ready native study geometry and the original
12 old_garden routes in a 3600×2400 world. It does not install geometry, alter
native contours, alter actors or consume RNG.

The two original blocked segments each gain one bend, the minimum added vertex
count that can replace a blocked straight segment. These are explicit authored
points; no globally shortest-distance claim is made.

- Original 0: `(362,2184) → (1062,2084) → (1342,2104)`
- Original 10: `(1342,2104) → (1542,2024) → (1882,1404)`
- The offsets relative to world bounds are `(1020,1980)` and `(1500,1920)`
- Width remains exactly 72 on all 14 resulting segments
- All non-endpoint metadata on split segments is copied into both new segments
- Camps, outposts, entry, boss, signs and actor positions remain exactly supplied

Original-to-prepared ordering is 0→[0,1], 1..9→[2..10] respectively,
10→[11,12], 11→[13]. Thus exactly ten original segments remain unchanged.
The four new segments [0,1,11,12] use native endpoint overlaps and bidirectional
sweeps at radius 51: half-width 36 plus player radius 15. The untouched ten use
their original formal radius 36. The complete production `_routes_reason`
predicate also passes, including all outpost-center and sign constraints.

## Evidence and retained failures

Only `tests/modular_study_routes_test.gd` is run for this evidence. It uses
`Session.layout` and the same native `StudyGeometry.install`, waits two physics
frames, then requires `physics_ready`. No Main, map admission, live battle tick,
editor import, asset rendering or wider geometry suite is run.

The command is:

`godot --headless --path . --script res://tests/modular_study_routes_test.gd`

Godot 4.6.3 uses copied existing import caches and isolated XDG directories under
`/tmp/godot-v115-routes/{data,config,cache}`. Each run retains source SHA-256s,
the exact console log, exit code and machine-readable native receipts.

- `routes-attempt01-*`: 14 checks, one failure, exit 1. Both proposed bends
  already passed native radius-51 sweeps in both directions. Requiring radius
  51 on every untouched original segment was too strict: original segment 5
  remains clear at its formal radius 36 but blocks at 51. No third route is
  changed and no width is reduced. The first helper and test are retained.
- `routes-attempt02-*`: 64 checks, one failure, exit 1. All route, movement,
  detachment, stable-output, geometry-preservation and formal-predicate checks
  passed. Only the fixture's assumption that a freshly installed native space
  cannot already pass `physics_ready()` before the explicit frame waits was
  false. Native readiness is checked by actual queries, not elapsed frames.
  The final test places its deterministic unready negative case before install.
  Both second-run source files are retained.
- `routes-unready-*`: only `-- --unready-only` was run after that fixture
  correction: one check, zero failures, exit 0. It verifies the exact unready
  refusal, unchanged input and absence of native space. It performs no native
  install or physics wait and does not rerun the previously passed 63 checks.
  The production helper is byte-identical to attempt02. The corrected complete
  fixture was not rerun, and these overlapping counts are not added into a
  claimed new full-run pass.

Each native report retains the original direct failures against contour 3
(rock) and contour 2 (arch leg), plus unsuccessful tighter candidates
`(1062,2134)` and `(1502,2004)`. The selected candidates pass. Player-radius-15
movement follows every new leg to the unchanged endpoints forward and back:
32 steps per direction for original 0, 30 per direction for original 10.
Every step remains native-clear. The exact four contours and 99 vertices,
geometry revision and presentation snapshot remain unchanged.

These results do not claim radius-51 clearance for the ten untouched original
segments, globally shortest routes, natural combat completion, other maps,
altered assemblies, art acceptance or performance improvement.

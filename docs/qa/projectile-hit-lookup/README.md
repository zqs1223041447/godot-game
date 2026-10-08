# Projectile hit lookup: focused CPU and equivalence evidence

Base: `840dc562c1fd3ed74ac34d221d3bdc922d837f59`, Godot 4.6.3 on Linux.

`Main._settle_projectile_events` previously searched the full resident roster
from its first entry for every hit. It now lazily builds one local lookup per
settlement call, retaining the first entry for duplicate IDs and the original
Dictionary references, including dead bodies until normal cleanup. A replaced
or resized roster invalidates the lookup. It never persists across calls. No
other production function changed; admission, sleep/wake, event ordering,
damage, death processing, reward RNG and save rules retain their code paths.

For the controlled 100-target / 180-hit batch, original first-match searches
visit 8,290 entries; the changed path visits the roster's 100 entries and does
180 lookups. The paired diagnostic alternates execution order for 36 pairs,
excludes four warmup pairs and excludes setup/cloning from timing. All 36
complete observations matched, including enemy state, event/damage traces,
particles, feedback, RNG and character snapshots. Measured mean settlement
CPU time was 12.73 ms before and 11.58 ms after (32 samples each).

Three short existing full-tick stress carriers also matched exact observation
bytes: 24 ticks without burn, 24 with ignite, and 150 with ember deaths. Each
starts with 100 real factory targets; controlled volleys use 180 actual
projectiles. The death case preserves 27 rewarded kills and inventory growth
from 38 to 42 items. Full-tick timings vary: no-burn mean 71.81 -> 52.39 ms,
ignite 89.19 -> 89.65 ms, ember deaths 32.54 -> 34.40 ms. These are descriptive
headless CPU samples, not a guaranteed full-tick gain or Windows FPS result.

- `projectile_hit_lookup_test.gd`: 10 checks, zero failures. Covers duplicate
  IDs, missing IDs, dead entries, knockback destination, live health changes,
  same-size replacement, same-array resize, and release between calls.
- `projectile_dense_equivalence_test.gd`: 3,126 checks, zero failures.
- Existing `exploration_main_flow_test.gd`: changed source 249 checks / 2
  failures, baseline 243 checks / 2 failures. Both failures are the existing
  hardcoded `version == 50` assertions; the current schema is 54. Entry
  rosters, offscreen residents, sleep/wake, damage, drops, completion and
  transactional save checks produced no additional failures. The count varies
  with generated descendants. This suite is not reported as passing.
- `git diff --check`: passed.

See `result.json` for the observations' matching hashes and measurements.
The paired diagnostic accepts a source file exported from the base commit via
`HIT_LOOKUP_BASELINE_MAIN`, an absolute JSON output path via
`HIT_LOOKUP_PROFILE_OUT`, and a fresh XDG data directory beginning with
`/tmp/godot-hit-lookup-`. Run it with the repository project and
`--headless --script res://tools/diagnostics/projectile_hit_lookup_profile.gd`.
The exported baseline and current Main use the same unchanged dependencies.
No long-duration check, rendering/FPS measurement, Windows export or packaging
was performed. Arbitrary external mutation of IDs or in-place roster reordering
inside settlement callbacks is outside the production contract and untested.

# Projectile hit lookup: focused CPU and equivalence evidence

Base: `840dc562c1fd3ed74ac34d221d3bdc922d837f59`, Godot 4.6.3 on Linux.

`Main._settle_projectile_events` previously searched the full resident roster
from its first entry for every hit. It now lazily builds one local lookup per
settlement call, retaining the first entry for duplicate IDs and the original
Dictionary references, including dead bodies until normal cleanup. A replaced
or resized roster invalidates the lookup. It never persists across calls. No
other production function changed; admission, sleep/wake, event ordering,
damage, death processing, reward RNG and save rules retain their code paths.

The current production settlement call chain keeps enemy IDs and roster entry
identity stable within the event loop. Both direct hits and the unchanged
explosion loop call `_apply_damage_packet`; resource, status, burn and death
settlement mutate the referenced enemy's fields without assigning its `id` or
replacing an entry in the original Array. Death processing queues offspring.
The reachable synchronous world/build callbacks update presentation, quotes,
stats and saves, without changing the roster. `_flush_monster_spawns` filters
into a new Array and admits queued offspring only after the entire event loop.
The singular burn advance and proliferation paths reached during damage do
not flush spawns. Thus same-length in-place enemy replacement or ID mutation
cannot occur through these current production paths. The existing replacement
and resize guards cover those separate supported roster changes; they do not
claim to cover arbitrary external callback mutation.

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

The two existing save assertion labels are exactly:

- `exploration_main_flow_test.gd:391`, `run()`:
  `Existing schema50 and original ownership validate at first launch`.
- `exploration_main_flow_test.gd:372`, `paid_atomic_reentry()`:
  `Final character remains valid existing schema50`.

Both require `snapshot().version == 50`; the current version is 54 and
`Rules.reason(snapshot()).is_empty()` succeeds. Their hardcoded version
expectation causes the failures on both the unchanged base and candidate.

After integrating the unchanged v125 source archive and east-only preview on
the same base, the focused lookup test passed all 10 checks and the isolated
headless movement preview passed all 46 checks. `git diff --check` passed and
the archived source tree matched its original commit exactly. The integrated
tree was not used to repeat the prior stress suite or native capture; the
separate preview's native 62-check evidence remains recorded in
`../v125-ranger-motion/`. The preview holds a locomotion frame for idle and
visual attack cues; authored Idle/Attack clips and other directions remain
unverified and absent.

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

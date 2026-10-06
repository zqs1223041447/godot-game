# v0.71 mist skitter roster evidence

The focused `tests/mist_skitter_roster_test.gd` gate passed on its first execution:
50,154 checks, zero failures, 7.070 seconds on Godot 4.6.3 Linux headless.
The shared editor import was completed separately before this run. The run used
its own temporary XDG directories; it did not read or write player saves.

## Selection contract

- Only canonical normal-progression `sunwell_terrace` tier II/wave 6 and
  tier III/wave 10 qualify. Fixed-wave test Sunwell has no journey tier and is
  unchanged, even though its wave is also 6. Tier I and both older maps remain
  unchanged.
- After the entire original Sunwell and special-patrol composition is finished,
  the first final `skitter` with rarity `normal` in each camp becomes
  `mist_skitter`. No candidate means no substitution. There is at most one per
  camp and three among the unchanged 36 map roots.
- Pure rules return the selected index; only its existing `template_id` changes.
  The original RNG sequence, slots, rarity, mechanisms, root identity,
  reward eligibility and terrain remain intact. Descendant spawning does not
  call this root-roster selection.

## Frozen-source comparison

`map_camp_state_4166822.gd.txt` contains the exact 6,444 source bytes from
`4166822ff7a487bb498c7086b20e2823e4e71edb:scripts/world/map_camp_state.gd`.
Its SHA-256 is
`6abe4a2320425bbcffb421d0b993573242a4fb877434f51d37b99ef2ffc5e11d`.
The fixture was extracted once. Each test process loads that script once,
removing only its global class name in memory, and reuses it throughout the
batch. Its ordinary-roll, Sunwell and map-compiler dependencies are shared
with the candidate; this is a frozen roster-algorithm oracle, not a frozen
entire-game build.

The batch covers 74 actual compiler profiles and 16 positive/zero/negative
seeds: 1,184 cases and 38,400 root entries. Expected substitutions are computed
independently by scanning each released final roster. All other entry bytes,
and the entire checkpoint after those explicit substitutions, match exactly.
There are 992 cases whose entire released checkpoint remains byte-identical,
492 allowed substitutions, 276 eligible camps without a candidate, and 96
cases where an earlier non-normal skitter is skipped for a later normal one.
Every storm-patrol case has zero mist skitters.

An additional eight full formations cover tiers II/III and all four special
choices, with health/shield modifiers: 288 actual roots are planned through
`MapCampAdmission`, retain their positions, fit the original terrain with
their actual radii, and register exactly 36 unique root identities per map.
The four solid spring basins and geometry snapshots remain unchanged.
Global and unrelated caller RNG state are also unchanged across the full gate.

Seed 43 with no modifiers yields admission indices `[6, 21, 25]` on both
eligible tiers, one in each camp. Seed 0 yields `[6, 25]`, with no eligible
candidate in the north camp. These are bounded deterministic examples, not
population-frequency estimates.

## Evidence and limits

- `roster.log`: engine output and completion marker
- `roster_report.json`: complete counts and deterministic examples
- `baseline_manifest.json`: original fixture provenance and digest
- `run_manifest.json`: command, runtime, isolation path, and before/after
  SHA-256 values for every production GDScript, the new gate and the oracle;
  no tracked input changed while the gate ran

`tests/v048_sunwell_layout_test.gd` has its independent expected composition
updated for the new final substitution. That historical suite was not rerun.
This evidence does not claim full historical validation, native UI review,
Windows performance, or actual death/reward settlement. Those integration
concerns are outside this roster-focused gate.

# v116 compatibility follow-on and merge boundaries

Base: `7918f5040db07c99d583d2cffb5b15965e90986b`.
Only `tests/exploration_map_plan_test.gd`, `tests/map_camp_admission_test.gd`
and QA documentation/evidence change in this follow-on. Every production file
is byte-identical to the v116 implementation commit. No runtime safety gate,
UI, map definition, economy, collision contour, resource or save code changes.

## Explicit geometry contracts

Both aggregate fixtures now separate the four ordinary maps from `ruins_garden`.
The native map is exercised, not skipped. Unknown future catalogue changes
cannot silently inherit an ordinary or untested branch.

The four-map loop retains its original layout, source roster, root identity,
capacity, body/range, modifier, factory, checkpoint and negative assertions.
The planner's old factory reference missed the already-existing planner-only
`map_outpost_id` field. It is now removed from the bare factory comparison only
after a separate strict check against authored source-group/ordinal positions,
actor/record IDs and each exact ordered outpost root list. Unknown fields still
participate in exact factory comparison; metadata is not generically ignored.

The native branches install the real assembly, prove readiness, prepare actual
v115 detours and use `PreparedMapEntry` ownership. They require unprepared,
forged, unready, wrong-owner and not-in-use requests to reject. They exercise
all three tiers, exact body/factory/checkpoint values, native route validation,
strict new boss identity, unchanged live runtime/RNG and native disposal.

## Exact executions

Only these two affected fixtures ran. Existing migration575, Main/menu174 and
boss9 checks are reused from their original evidence; none was rerun.
No combat, rendering, asset import,600-second run or wider suite was started.

### Exploration planner

- `compat-plan-attempt01`: complete affected fixture,334 checks,24 failures,exit1
- All legacy layout, invalid-contract and bookkeeping assertions passed
- Twelve old-map and six native factory assertions failed because their reference
  omitted the attached outpost ID; six new native landmark assertions incorrectly
  compared admitted root lists to unadmitted authored landmarks
- `compat-plan-identity-parse`: test-only missing continuation token,exit1;
  no assertions ran. Exact failing source retained
- `compat-plan-identity`: **273 checks,zero failures,exit0**, using
  `-- --identity-only`. It reruns the affected positive/identity paths for all
  four original maps and the complete native contract, including the strict
  outpost mapping check. The previous passing layout, legacy negative and
  bookkeeping paths were not repeated
- No new complete-fixture pass is claimed, and overlapping counts are not added

Command from the project root, with isolated XDG directories under
`/tmp/godot-m1-v116-compat-plan/{data,config,cache}`:

```
godot --headless --path . --script res://tests/exploration_map_plan_test.gd
godot --headless --path . --script res://tests/exploration_map_plan_test.gd -- --identity-only
```

### Camp admission

- `compat-camp-attempt01`:51,605 checks,three failed timing assumptions,exit1
- A headless physics server may already synchronize immediately after install;
  absence of elapsed frames cannot prove unready collision
- The corrected test removes one real candidate body from its native space,
  so actual readiness probes fail deterministically. The successful candidate
  still installs the untouched assembly and waits physics frames
- `compat-camp-attempt02`: **51,605 checks,zero failures,exit0**
- Original four-map branch:22,326 checks,340 staged groups,240 rejection groups
- Native branch:90 lawful tier/modifier profiles,360 actual camp/boss groups,
  and46 explicit rejection cases; out-of-tier modifier combinations reject
- The second exact-fixture run completed before narrowing to a readiness-only
  follow-up, so both full runs are retained honestly; no further rerun followed

See `compat-camp-README.md`, exact run manifests, results and retained sources.
Both suites use Godot4.6.3 with existing imports. Isolated filesystem destinations
and all test failures are retained; no production defect is inferred from the
fixed test-reference/readiness assumptions.

## Does the default main-game path change?

This compatibility follow-on changes no main-game function or route.
The underlying v116 feature has these explicit changes relative to main:

- Default draft remains `old_garden` tierI; the ordinary animated hero is unchanged
- Existing four maps still use synchronous `start_map`, original rectangular
  geometry and the same normal save/fee/reward transactions
- The normal town menu now calls `open_map`; for an ordinary map it immediately
  delegates to unchanged synchronous entry. Only the new map waits for native
  preparation; historical test-town options do not expose it
- Opening a valid old save automatically migrates53→54 with an exact original
  backup and only one added zero tier key. Old active/pending identity and owned
  data remain unchanged
- Only `ruins_garden` uses native entry/retry, its own progress key and strict
  boss ID. It is an additional map choice, not a replacement of old garden

## Concrete merge and release risks

1. **Dependency series, not an isolated last-commit patch.** Current main is
   `e2fa6db67fb9c4c7f201c795df12bdeb9b699832`. Before this test/docs follow-on,
   v116 is seven commits ahead: v110 hero adapter, v111 module study, v112 native
   study, v113 ground, v114 evidence, v115 preparation and v116 formal entry.
   That series differs in288 files; main does not contain prepared_map_entry.gd.
   Cherry-picking only the v116 implementation is not self-contained. Review
   and merge the complete required dependency series, or explicitly assemble
   its required source/assets; do not call this just a two-test/main patch.
2. **Save rollback boundary.** Schema53 binaries correctly protect/reject a
   schema54 save. Returning to an old binary requires the matching original
   `build_save.json.v53-backup.json` (or the relevant original-version backup).
   That backup predates new54 progress. Do not promise lossless downgrade of
   later progress or overwrite a progressed54 save during rollback.
3. **Prepared-selection wording remains confusing.** Changing the map dropdown
   still displays the previous authoritative draft until the user presses
   准备地图. The launch guard prevents unprepared selection from entering, and
   the actual new-map entry works. Clearer selection/draft messaging remains
   a separate UI task; it is not silently included here.
4. **Completion evidence has a precise limit.** New-ID completion/claim isolation
   is tested at the existing canonical boundary on a real admitted native run.
   Native movement and prior same-assembly combat evidence exist, but no new
   natural full-clear on the formal native identity, all-tier live navigation,
   Windows build or performance run was performed. This branch does not claim
   those outcomes or a complete repository-wide regression pass.
5. **CI does not provide an additional gate.** The implementation commit had
   zero remote checks and statuses. Local focused evidence is the available
   validation, not an automatically passing required CI configuration.

Main remains untouched. No pull request, merge, Windows package or deployment
is part of this source backup.

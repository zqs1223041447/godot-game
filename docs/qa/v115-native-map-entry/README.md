# v115: native study preparation before map entry

Base: `f4a7beded3e5e186325488e0d1d5521e0b2fd101` (v114).
Branch: `codex/v115-native-map-entry`. This is a source-only, isolated study
entry. It does not change the formal old_garden catalogue, map IDs, economy,
progression, root roster, default hero, v113 ground or main branch.

## Entry and ownership

- `ModularStudySession.prepare_entry(Main)` builds a detached native geometry,
  waits two physics frames, requires actual query readiness, prepares the two
  route detours and validates the optional study hero before any entry fee.
- `PreparedMapEntry` is a one-use resource owner. Its captured context includes
  Main/model identity, world/draft/model/run revisions, draft contents, save path,
  completion state, RNG seed/state, monster lineage checkpoint and templates.
  Cancellation, stale context or failed admission disposes its native resources.
- `Main.start_map_prepared` and the optional planner argument independently
  recheck ownership, native readiness, bounds, map/entry, unchanged non-route
  landmarks, ordered complete route chains, width/clearance and all 25 actual
  roots. A caller-supplied ready/validated Dictionary cannot bypass this work.
- The existing normal fee/save transaction is reused. After it succeeds,
  `restart_run` adopts the exact object used for admission. Nothing is rebuilt
  between validation and installation; the handle then relinquishes ownership.
  Reentrant cancellation/duplicate prepared entry during the save signal cannot
  release that in-use geometry or spend twice.
- A later ordinary restart uses the unchanged normal planner, releases native
  resources and restores matching ordinary geometry/routes and normal hero.
  A failed retry save leaves the existing study untouched. Town return also
  releases study resources through the existing geometry transition.
- The standalone study launcher uses this new prepare/enter path. The old
  post-entry `Session.install` remains for the recorded v112/v114 fixtures.
  The normal `start_map` path remains the default; no new formal map choice
  or production UI entry is added.

Route details and the exact scope of clearance are in [ROUTES.md](ROUTES.md).
Only original route 0 and 10 gain one bend each. Width stays 72. New legs pass
bidirectional native radius-51 sweeps; the other ten keep radius 36. Original
route 5 does not support the extra radius-51 claim and was not changed.

## Focused verification and retained failures

Godot 4.6.3, headless, existing imported assets. No editor import, rendering,
v114 combat replay, 600-second run or old full-suite rerun. Tests use isolated
`/tmp/godot-m1-v115-entry/{data,config,cache}` and an immutable copy of the real
v114 earned save: four shards, tier-I completion and only tier-II unlocked.
No currency, unlock or reward is fabricated for these tests.

Environment for both runs:

```
XDG_DATA_HOME=/tmp/godot-m1-v115-entry/data
XDG_CONFIG_HOME=/tmp/godot-m1-v115-entry/config
XDG_CACHE_HOME=/tmp/godot-m1-v115-entry/cache
PREPARED_ENTRY_FIXTURE=$PWD/docs/qa/v115-native-map-entry/earned-v114-save.json
```

1. `godot --headless --path . --script res://tests/prepared_map_entry_test.gd`
   - `entry-attempt01-*`: 513 checks, two failed assertions, exit 1
   - Every cancellation, waiting/concurrency, stale-context, native readiness/
     disposal, route/landmark revalidation, fake-owner, locked-tier, real save
     failure, insufficient-funds, same-instance installation, exact-once fee,
     duplicate-use, reentrant cancellation and town-release check passed
   - The two failures were the same test-reference error at tier I and II:
     comparing installed roots to raw planner bytes omitted the existing Main
     `accuracy`/`evasion`/`armour` defaults. The corrected reference applies
     Main's unchanged `_apply_source_actor_profile` before exact comparison
   - The exact original test is retained in `entry-attempt01-test.gd.txt`
2. `godot --headless --path . --script res://tests/prepared_map_entry_test.gd -- --success-only`
   - `entry-success-retry-*`: 130 checks, zero failures, exit 0
   - Rechecks only the two success cases with the corrected exact root reference
     and adds the ordinary-restart failure/success/resource-release case
   - This overlaps the first run; counts are not added into a new full-suite
     total. The corrected complete focused fixture was not rerun
3. Existing `parse-main.log`: exit 0. Route evidence retains its original failed
   runs and the narrow corrected unready check, as described in ROUTES.md

The final source hashes and both machine-readable entry reports are retained.
The earned fixture is byte-identical before/after. Actual saved envelopes were
reloaded and compared to the committed model. All test Main instances are
paused; admission tests do not simulate combat.

## Limits

This does not claim a new formal map, natural combat full-clear, every seed or
monster size, exhaustive external callback reentrancy, Windows behavior,
performance improvements, final art acceptance or an old full-regression pass.
Existing v112-v114 combat, ground and completion evidence is reused unchanged.

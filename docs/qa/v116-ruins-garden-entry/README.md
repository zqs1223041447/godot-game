# v116: 遗迹庭园 / ruins_garden

Base: `9ad500573285146af473828d5549f659b94f1c38` (v115).
Independent branch: `codex/v116-ruins-garden-entry`. Source only; main is unchanged.

## Player-facing contract

In the normal town map device, select **遗迹庭园**, select its tier/modifiers,
choose **准备地图**, then **开启地图**. Native preparation occurs before admission.
The existing four maps retain their identities and definitions. The new map is
not offered in the historical free test-town catalogue.

- `ruins_garden` owns its own tier key, active run and pending reward identity
- Six 3/5-root outposts supply 24 ordinary roots plus one boss
- Tiers use waves 1/4/8, costs 0/4/8 shards and base rewards 4/8/12, including
  unchanged existing modifier bonuses. No new economic action or reward button
- The boss has its own strict `ruins_garden_slam` identity and exact existing
  garden-slam timing, radius, targeting and damage values
- Four unchanged native contours, the two v115 detours, original module images
  and v113 grass/soil/stone ground are reused. No new art download or render
- The default hero remains the existing animated character. Static directional
  study presentation requires the explicit study option; formal entry passes false

Schema54 migrates a valid53 envelope by changing its version and adding only
`best_tiers.ruins_garden = 0`. Every old map progress value, active/pending map,
item, reward counter and revision is preserved. Exact old bytes are backed up
before atomic persistence. Complete historical50–53 journey validation remains
frozen. See [migration evidence](migration-README.md).

## Async entry and retry

`Main.open_map` is the explicit async UI boundary. Old `start_map` remains
synchronous and rejects the new map without prepared native geometry. The
planner and base rectangle geometry also reject a native-map fallback.

Preparation builds a detached candidate, waits for native readiness, validates
routes and all actual roots, then reuses the canonical save/fee transaction and
transfers that same object. Closing the panel, switching selections, stale
context, native failure or save failure cannot spend or replace the live map.
Concurrent requests have one owner. The current game process is held during the
two-frame native preparation and restored when it settles.

Normal restart dispatch for this map prepares another `ruins_garden` candidate
and uses the existing same-profile replace-run transaction. It retains its own
ID, modifiers, tier and fee. Failure keeps the original native instance and
saved run; success transfers the new one and releases the prior resources.
Town return releases the final candidate. Old garden's synchronous ordinary
entry still has its original twelve routes and 25 roots.

## Verification, including retained failures

Godot4.6.3 with existing imports, isolated XDG directories. No natural combat
clear,600-second run, asset regeneration, Windows export or old full-suite rerun.

- Migration: **575 checks, zero failures**, exit0. Full scope and the initial
  test-only parse error are retained in `migration-*`
- Entry attempt01:72 checks, one failure. Actual menu/prepare worked, but the
  old boss attack correctly rejected the new map ID before save
- Entry attempt02:the same72 checks and failure, adding exact menu feedback to
  identify that strict boss-origin rejection. No success was claimed
- Entry attempt03: **174 checks, zero failures**, exit0, after adding an explicit
  new-map boss attack ID with the original numeric profile
- Boss-only follow-up: **9 checks, zero failures**, exit0. New and old identities
  are separate; cross-map mixing rejects; exact original numeric values and the
  real detached boss/runtime attack mapping are checked
- The final script adds only the isolated `--boss-only` dispatch after attempt03;
  the exact attempt03 script is retained. No full entry rerun is claimed

The entry test uses actual town OptionButton/button signals, real Main, real
native geometry and actual fee/save operations. It covers close/switch/native
failures, unprepared synchronous rejection, duplicate clicks, same-object
transfer, exact native map identity, modules/ground acceptance, normal animated
hero, saved reload, paid failure, ordinary-button retry, exact-once fee,
insufficient funds, disposal and subsequent unchanged old-garden entry.

Completion/claim checks explicitly invoke the existing trusted canonical
completion boundary on the actually admitted native run. They prove new-ID
progress/pending/claim isolation and duplicate rejection. They are controlled
state-boundary fixtures, not physically earned kills or a gameplay-clear claim.
The original v114 earned source fixture remains byte-identical.

The migration run preceded the explicit boss-binding change; its recorded
catalog hash is preserved rather than rewritten. Its six migration production
files remain unchanged after the passing run. Later entry/boss tests validate
the final binding. A final-source manifest records the shipped source bytes.

## Native UI review

A separate normal native-window review at20:57–20:59 UTC used the actual town
map device: select 遗迹庭园, prepare, open. The HUD showed 遗迹庭园 I and25
remaining roots, and ordinary D-key movement worked. See [native entry capture](native-entry.png).
This verifies the reachable player-facing entry and a short movement check,
not natural combat completion or performance.

Before pressing 准备地图, the summary still describes the previous authoritative
draft (旧庭). After preparation it changes to 遗迹庭园. This is retained existing
draft behavior but can be confusing; clearer unprepared-selection messaging is
follow-up UI work, outside this batch.

Historical aggregate fixtures such as `exploration_map_plan_test` and
`map_camp_admission_test` enumerate every catalogue entry while assuming each
supports synchronous rectangle geometry. They have not been adapted to the
explicit native-only entry contract and were not rerun. Native safety was not
weakened to satisfy that old assumption. A future aggregate pass must separate
the old four-map default contract from this new prepared-native contract.
No full-regression or merge-readiness claim is made here.

## Reproduce the focused entry test

```
mkdir -p /tmp/godot-m1-v116-entry/{data,config,cache}
XDG_DATA_HOME=/tmp/godot-m1-v116-entry/data \
XDG_CONFIG_HOME=/tmp/godot-m1-v116-entry/config \
XDG_CACHE_HOME=/tmp/godot-m1-v116-entry/cache \
godot --headless --path . --script res://tests/ruins_garden_entry_test.gd
```

Add `-- --boss-only` for the isolated mapping follow-up. For a normal visual
review, use a separate `/tmp/godot-m1-v116-review` XDG root and `godot --path .`.
Use only isolated copies with this independent source branch.

## Source dependency scope

Every touched production file has one required responsibility:

1. `world/map_catalog.gd`: selectable own ID/name/root budget/boss binding; exclude
   the async-only map from historical free test-town options
2. `world/normal_map_catalog.gd`: existing costs/rewards with explicit1/4/8 waves
3. `world/normal_journey_state.gd`: current five-map keys and frozen53 four-map keys
4. `save/canonical_build_rules.gd`: complete53 decoder/validator and current54 gate
5. `save/canonical_build_store.gd`: initial/default and actual file migration chain
6. `save/long_stride_gem_migration.gd`: keep52→53 validating53, not newly current54
7. `save/ruins_garden_migration.gd`: new exact53→54 map-key migration
8. `canonical_game_state.gd`: truthful53 migration notice only
9. `world/exploration_map_layout.gd`: explicit native map layout, names and25-root sites
10. `world/map_camp_state.gd`: explicit eight-root source groups for the new map
11. `world/map_camp_admission.gd`: explicit native ID/owner/readiness requirement
12. `world/exploration_map_plan.gd`: reject unprepared new-map planning
13. `world/map_geometry.gd`: forbid rectangle fallback for native-only ID
14. `studies/modular_study_geometry.gd`: preserve new authority ID through native install/refresh
15. `studies/modular_study_routes.gd`: validate unchanged authored detours for explicit new ID
16. `studies/modular_study_session.gd`: own-ID preparation/retry and optional study hero
17. `main.gd`: async entry/retry ownership, existing atomic transaction reuse and cleanup
18. `ui/town_service_panel.gd`: await actual launch, reject repeat clicks and cancel on dismissal/change
19. `visuals/dimensional_prop_manager.gd`: explicitly map new ID to validated existing modules
20. `visuals/static_arena_layer.gd`: explicitly enable the existing retained ground/marks
21. `visuals/study_ground_layer.gd`: accept new ID while keeping exact contour/hash/resource checks
22. `monsters/map_boss_profiles.gd`: required strict new-map boss identity; no value rebalance

Only the two new targeted tests and their evidence accompany these dependencies.
No map-camp legacy layout, old map definition, economic table, asset, shader,
combat algorithm, main branch or unrelated feature was changed.

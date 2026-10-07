# v101 Ginkgo inner-circle / outer-annulus reference

This is a bounded update to the current `maps-ginkgo_arcade` F8 card. The catalog changes only `exploration_maps.maps.ginkgo_arcade.boss_definition`, its current `description`, and a separately named top-level `ginkgo_inner_outer` policy/evidence section. It does not alter geometry, spawn records, the other three map cards, economy, save schema53, source49, equipment51 or runtime version.

The historic top-level `catalog.ginkgo_arcade` is the v83 single-circle archive. It remains byte-for-byte historical data. The old exploration geometry/Main reports also remain unchanged and are not presented as evidence for this new attack. The current card explicitly distinguishes them from the new report.

## Actual Main evidence reused

The report is [first/main-result.json](../v101-main/first/main-result.json): 453 checks, 0 failures, 16 probe groups. [stdout.log](../v101-main/first/stdout.log) and [run.json](../v101-main/first/run.json) record the run, original input hashes and command. [formal-initial-save.json](../v101-main/first/formal-initial-save.json) is the actual lawful fresh schema53 character snapshot.

The formal map admits all 36 ordinary roots and the natural boss. The held-input route uses actual Main ticks to leave the first circle and reenter the safe inner area before the second event. Boundary, resource, wall, freeze and death cases are explicitly controlled integration probes; this is not natural-play footage or a DPS, performance or full-release claim. The reference retains that distinction and does not create a new equipment model.

The two example event dictionaries and packets are copied from `groups.held_input_leave_reenter.trace`; initial/outer snapshots come from the same group. `entries[0].boss` and `.policy` are the actual natural source and its attack-speed-scaled policy. The recorded base recovery is 1.9, while this actor's actual recovery is about 1.84793; the exporter never feeds unscaled base recovery to the natural actor. No scheduler or Main instance is executed by this reference export.

Main453 ran before the final guard that rejects annulus inner radius 0. The legal inner radius 130 and other valid paths are unchanged. The final runtime is covered by [779/0 focused runtime checks](../v101-runtime/validation.json) and [their log](../v101-runtime/runtime-first.log.txt). The original Main runtime SHA is `85f653485d3da1392591fc9f3081628fe9dac8aa689ff08804cf7b8d1bed5512`; final runtime SHA is `e846533c6f6cd1c9e5c4726a17c0ebfddaae69add0ac8e22a361fbc6a1f773cb`. These are distinct source checkpoints; no final-source Main rerun is claimed.

## Bounded export and exact preservation

`tools/ginkgo_inner_outer_reference.gd` reads the current boss definition, current map description and authoritative player-radius/schema constants. It validates the retained character through the canonical save decoder and validator. It checks recorded event identity, geometry, schema, timings and damage components against the current boss authority, then serializes only the new fragment. There is no full `export_reference.gd`, scene, map, combat, save, source-coverage or art run.

`run-export.py` fingerprints dependencies and evidence, uses isolated temporary Godot data/config/cache directories, and records export status/logs. `merge-fragment.py` performs two exact raw JSON value-span replacements and appends one new policy; all unrelated original tokens and float spellings remain. The builder change is restricted to the current Ginkgo conditional in `exploration_map_body`.

`check-reference.py` checks exact card scope, preserved raw top-level and nested tokens, unchanged historical archives, source/evidence hashes, numeric facts, actual event/fixture provenance, local links, unique anchors and reproducible HTML. The rest of the page, excluding the current Ginkgo article, its search record and the overall data fingerprint, must remain byte-identical. It does not rerun Godot.

Run `python docs/qa/v101-reference/check-reference.py` for the deterministic static check. The one-time exporter and merger deliberately reject overwriting their original evidence. Export and final verification status are in `export-run.json` and `final-result.json`; preservation detail is in `catalog-format-preservation.json`, `preservation.json` and `card-sha256.json`.

The first static check caught an expected output dependency (`index.html` changes after export) and a Godot JSON roundtrip shift of several report doubles by one ULP. `first-check-observations.json` and `first-merge-preservation.json` retain that result. The corrected merge projects all five actual Main example dictionaries directly from the original report JSON, retaining exact values; the raw Godot export is unchanged. Output-dependency hashes are checked against the pinned baseline, while all other export inputs are checked against final files. No Godot rerun occurred.

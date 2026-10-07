# v114 modular study closure

Base: `bf8aacfb2c13b96fb6f489338fa7a7252ab190df` (v113). Only a focused test, this evidence and technical entry notes are added. All tracked gameplay/art/source files under the paths listed in source-scope.json remain byte-identical to the base. Main remains e2fa6db; this is independent study-branch evidence.

## Actual execution

The single full run used Godot 4.6.3 with `/tmp/godot-m1-v114-closure/{data,config,cache}` as isolated XDG directories. Existing verified v113 imported resources were reused; no editor import or asset rendering was repeated. Invocation:

`godot --headless --path . --script res://tests/modular_map_closure_test.gd`

- attempt01.log / attempt01-exit-code.txt / attempt01-inputs.txt: 114 checks, one failure, exit 1
- attempt01-source.txt is the exact source loaded for that run, confirmed against the original recorded SHA-256
- attempt01-result.json and result.json contain the same original full report
- The sole failure was the last fixture assertion requiring historical save version 50. The actual earned save was already valid current version 53. Production rules and saves were not changed
- The assertion now uses Rules.VERSION. Only `-- --saved-only` was run against that same earned save: 9 checks, zero failures, exit 0, in saved-only.log/result/input/exit files. It creates no Main, enters no map, settles no damage and claims no reward. It preserves exact save bytes, original full report, and makes zero save attempts

The narrow follow-up overlaps the final full-run save check; these counts are not added into a new claimed full-suite total. The corrected complete fixture was not rerun.

## Covered outcomes

- Lawful starter/tier-I old_garden admission and unchanged original 25 roots; six outposts, no gear or currency grant
- Native radius-15 swept spatial paths to all six outposts, boss and entry; separate entry paths to each original actor position. Each movement segment is checked, without live player relocation, actor changes, battle ticks or RNG consumption
- The inherited complete_boss_first helper is unchanged: controlled real Defense lethal receipts, original four boss children, held-child completion block, bounded lineage drain, exactly25 root rewards, all six outposts cleared, retained source records, repeated-death/completion and claim rejection atomicity
- Pending save reload retains tier-I completion and exactly4 pending shards. Actual town claim credits4 once; second claim rejects. Claimed model reload matches and has no active run or pending receipt
- Town removes native study collision, module instances, ground/marks and hero selection, restoring original town presentation
- All 12 original width72 route constraints were evaluated using the real formal planner predicate. Two fail at radius36; all six center/sign checks pass. This is a future formal-entry gap, separate from the successful player-radius paths

No natural full-clear combat, pickup collection, every monster size/seed, new fault-injection matrix, Windows performance or final-art acceptance is claimed. Actual v112 movement/projectile/three-monster gate and native three-kill observations, plus v113 local native ground observations, are reused from their existing records. Current Main already applies `_geometry.legal_point` at each actual descendant admission; this batch does not claim exhaustive descendant path coverage.

## Next integration conditions

See `../../art/MODULAR_STUDY_FORMAL_ENTRY.md`. Before adding a formal choice: prepare/synchronize native geometry and validate before fees/save; adopt that exact prepared geometry; reconcile the two authored route conflicts; explicitly define the new ID/root-budget/progression/presentation policy. The present study remains isolated and does not add any of those production changes.

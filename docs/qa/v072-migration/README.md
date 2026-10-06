# v0.72 strict save45 → save46 migration

Result: **347 checks passed, 0 failed**, one focused Godot run, **23.762 seconds**. Exit 0; zero script or engine errors; captured production, fixture and test inputs were unchanged across the run.

- `20261006T070613579808Z-receipt.json` records the exact command, isolated XDG directory, input SHA-256 values and run outcome
- `20261006T070613579808Z-checks.json` records all ten migration cases, original source-byte digests and preserved ownership/recovery counts
- `20261006T070613579808Z-run.log.txt` is the complete raw engine output
- `run-focused.py` runs only `tests/glove_ring_affix_migration_test.gd`, after the parent’s shared import, with a 55-second watchdog and a fresh `/tmp/godot-m1-v072-migration-*` profile

## Source provenance

The three `docs/qa/v070-gameplay/fixtures/{selected-above,selected-below,refunded}.json` files are the existing schema45 actual-Main fixtures. They are read byte-for-byte as supplied, never generated from the new serializer or relabeled. Their SHA-256 digests are recorded in the result and receipt.

The five schema45 sample states use those existing owned items with the original `docs/qa/v071-build-comparison/routes.json` routes, level19 and budget23, matching the prior comparison’s construction. These derived samples are explicitly separate from the genuine serializer-byte cases.

Earlier-chain checks reuse the independently captured schema44 IR, ZO and physical-to-fire conversion fixtures under `docs/qa/v070-migration/fixtures/`. The previous Precise Technique migration must produce exactly45; the new migration then produces46. Active-map and pending-map-reward cases are derived from legal `Journey.start`/`Journey.complete` planners and retain the original recovery items.

## Verified boundaries

- Only save `version` changes; existing items, rolls, UIDs, location order, equipped slots, points, currency, progress, journey and migration ledger remain equal
- Current-model stats, combat snapshots, basic casts, every skill-group cast, equipped items, pending recovery and wallet outputs are identical before/after migration
- Exact raw `.v45-backup.json` bytes precede the one successful commit and one notification; repeated/current reopen performs no migration rewrite
- Frozen45 validates equipment vocabulary39 and source policy45 before optional callbacks, even after warming current item metadata with one of the four new affixes
- New affix injection, malformed envelopes and native source/budget/location/binding/ledger violations cannot create a backup, mutate state, write the target, or bypass later target protection
- Backup failures, conflicting backups, external writers, real `.tmp` collisions and failed replacement of an already loaded current state retain the correct source, live memory and disk receipt; a removed temporary fault permits one successful retry
- The constructor and complete legacy chain reach46, while the prior44→45 migration remains frozen; source policy stays45 and historical save-to-equipment mapping stays explicit

No legacy suite, export, long stress run, stat formula, UI behavior or equipment catalog was changed by this migration work.

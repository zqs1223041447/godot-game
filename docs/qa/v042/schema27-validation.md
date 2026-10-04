# Schema27 equipment-affix migration

Schema27 admits the four new random-equipment families. The migration changes only `version: 26` to `version: 27`; items, UID allocation, bindings, metadata, currency stacks, revisions, point budgets, active journeys, and pending rewards are compared as complete snapshots.

## Historical boundary

`CanonicalBuildRules.decode_v26` and `reason_v26` keep the existing schema26 envelope and journey validation. For `expected_version < Equipment.CURRENT_VOCABULARY`, both `_decode` and `_reason` explicitly validate each nonempty equipment payload against `min(expected_version, Equipment.CURRENT_VOCABULARY)`. The historical `_reason` check precedes the current item metadata cache, so a warmed schema27 item cannot make a schema26 injection valid. Current27 uses the existing complete `Items.decode_instance` validation and `Items.metadata_for_items` typed positive cache without a redundant equipment-validation pass. An optional talent validator cannot bypass the historical equipment check. Source talent execution remains vocabulary25.

`NormalJourneyMigration.migrate_v25` remains pinned to26 and validates its result with `reason_v26`. `EquipmentAffixMigration.migrate_v26` validates the old envelope before duplicating it and changing the version. The default and file-loading chains apply this final step once. The existing original-byte backup, backup-collision protection, external-write comparison, atomic primary write, rollback, blocked-save and retry behavior is retained.

## Frozen fixtures

The three literal fixtures in `tests/fixtures/v042_affixes` were exported by the external `schema26-fixture-capture.gd` script with `--main-pack` pointing at the exact released v41 `game.pck`, SHA-256 `f6c00b1e27a6e8c890d5c28cac7e89b19df46d8f14e18a00266118344119f0fa`. The source release is `15bf503113105538984c4e8dc267b336fb237674`, application0.41.0/schema26. The script refuses a different application version or schema. It does not manufacture historical fixtures by decrementing a current-code version.

- `v26-default.json`: untouched released default
- `v26-active.json`: paid tier2 active run with two normal modifiers and `frost_patrol`, real rolled and recalibrated gear, changed F1 binding, six remaining currency shards, level4/XP6, 90 root kills, two claimed gems, one claimed flask, and one unclaimed gem ordinal
- `v26-pending.json`: the same released gameplay state after completing the active run, with the twelve-shard map reward still pending

The capture used released game APIs for loot, binding, map starts/completions, reward claims and crafting, inside `/tmp/godot-m1-v042-fixture/run3/{data,config,cache}`. Each output retains literal CRLF and surrounding whitespace. `manifest.json` records byte counts, hashes, pack identity, capture-script hash and isolation. Real user saves were not accessed.

## Targeted verification

Run only after the coordinated new-tree import and catalog interface are ready:

```sh
XDG_DATA_HOME=/tmp/godot-m1-v042-migration/run2/data \
XDG_CONFIG_HOME=/tmp/godot-m1-v042-migration/run2/config \
XDG_CACHE_HOME=/tmp/godot-m1-v042-migration/run2/cache \
timeout 45s godot --headless --path . --script res://tests/equipment_affix_migration_test.gd
```

Use a fresh isolated run directory for a rerun, so existing collision fixtures do not influence the result. The final raw output is `schema27-migration.log`; `schema27-tested-files.json` records the exact test source and relevant dependency/fixture hashes.

Initial complete migration result: **334 checks, 0 failures**, exit0, Godot4.6.3. No script/parse/runtime errors appeared in that log. `schema27-tested-files.json` deliberately retains the exact inputs of that run, before the subsequent current-version cache optimization described below.

Coverage includes all three released fixtures, complete-state equality except version, exact-byte backup, one primary write, no rewrite on current reread, a fresh independent reopen, existing backup collision, backup failure, write failure and retry, external writes after backup, all four new families on all four eligible bases, warmed metadata rejection for old25/26, booleans/fractional/string/null rolls and tiers, rejection before backup creation or overwrite, derived-field injection, malformed envelope/journey, pinned25-to26 behavior, and the complete13-to27 chain with original BOM bytes.

The initial run completed312 checks with two failures in an assertion that assumed the released binding API kept its changed F1 binding at array index0. The released API appends that binding. The assertion now verifies binding identity; this required no production-code change. The final suite also adds malformed-roll checks on the actual frozen old equipment payload. This validation is scoped to the migration boundary; it is not a full gameplay or history-suite pass.

## Current-version cache follow-up

Review identified that the explicit historical-vocabulary gate was redundantly validating current27 equipment before its positive metadata cache. The narrow follow-up conditions that gate on `expected_version < Equipment.CURRENT_VOCABULARY` in both `_decode` and `_reason`. Existing current payload validation remains mandatory through the original item decoder/metadata validator and exact typed cache keys. Backup, persistence, rollback and migration-chain code did not change.

Only the affected pure vocabulary/cache cases were rerun:

```sh
XDG_DATA_HOME=/tmp/godot-m1-v042-migration/vocabulary/data \
XDG_CONFIG_HOME=/tmp/godot-m1-v042-migration/vocabulary/config \
XDG_CACHE_HOME=/tmp/godot-m1-v042-migration/vocabulary/cache \
timeout 30s godot --headless --path . --script res://tests/equipment_affix_migration_test.gd -- --vocabulary-only
```

Final changed-boundary result: **128 checks, 0 failures**, exit0; no script/parse/runtime errors. The isolated data directory contains no JSON saves because this run only exercises pure validation. `schema27-vocabulary.log` contains raw output; `schema27-vocabulary-tested-files.json` records the final rule/test sources and relevant dependency hashes, verified unchanged after the run. The earlier334-check result supplies the unchanged backup/write/rollback evidence; those file-writing cases were intentionally not repeated for this cache-only refinement.

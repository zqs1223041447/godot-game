# v0.82 source cold ailment duration and schema49

This slice admits only node `14209`'s complete original entry, `20% increased Duration of Cold Ailments`, as `cold_ailment_duration_increased = 0.20`, mode `increased`. The current source policy is49. Explicit policies14–48 retain their former vocabulary. No percentage family, chance, condition, effect magnitude, Brittle producer, or additional node family is admitted. The original source tree, IDs, links and values remain unchanged.

The source consumer group names the real `CombatData.snapshot` stat transfer, `SkillCompiler` frost duration calculation and derived Frost Lock policy. The gameplay slice separately verifies their runtime behavior. This source slice does not claim gameplay acceptance from a text anchor alone.

## Focused evidence

- `source-report.json`: exact-string rejection, frozen48 whole-graph differential, mixed unsupported line retention, both actual eight-point routes, save-first allocation and refund rollback, native49 reload, and current-policy source monster metadata
- `migration-report.json`: released native48 fixture →49, pure version-only migration, exact original-byte backup, no gifts, strict old48/native49 legality, complete default migration chain, invalid-save rejection, backup collision, external writer and atomic-save failure behavior
- `frozen-source-provenance.json`: frozen v0.81 parser/runtime provenance at `a57a9c0c`; only global class registration and the frozen parser dependency are adjusted
- `tested-input-sha256.json`: final input hashes for this focused run
- Attempt logs are retained separately; a corrected run does not replace its earlier log

After the parent's one unified import, both focused tests passed on their first run under Godot4.6.3 in separate temporary XDG directories: source8768 checks/0 failures in8.817s, migration145 checks/0 failures in21.566s. Both processes exited0 with no `ERROR` or `SCRIPT ERROR`. Total:8913 checks. No historical aggregate suite or retired600-second soak was run.

## Real route fixture

`tests/fixtures/v082/cold_ailment_duration_fixture.gd` preserves owned items and uses a lawful level4/eight-point fixture. Every paid node is then allocated with the actual model command. It is shared with gameplay checks, so formal checks do not construct ad hoc rare items.

- Witch: `54447 → 57226 → 21678 → 32210 → 8948 → 27659 → 37671 → 27415 → 14209`
- Shadow: `44683 → 38129 → 11334 → 15549 → 20546 → 21301 → 37671 → 27415 → 14209`

At the seven-point prefix the new stat is zero and one point remains. Target allocation spends the eighth point and grants0.20. Target refund restores one point and removes the grant. Failed allocation or refund preserves the prior memory, disk and stat. Disconnecting the prerequisite remains illegal.

## Migration and compatibility boundary

`ColdAilmentDurationMigration.migrate_v48` validates the complete old48 envelope before duplicating it and changing only `version` to49. The older elemental conversion migration still stops at48 and uses frozen48 validation. `CanonicalBuildStore` preserves the original input bytes in `.v48-backup.json` before atomically publishing49. It does not add items, points, rewards, or a new equipment vocabulary; equipment remains46.

Player stats now contain an explicit zero default for the new typed stat. Existing valid source allocations have no new numeric effect. This is not a claim that the player stats dictionary is byte-identical to the pre-v0.82 dictionary, because that default field is new. Gameplay snapshot zero-omission compatibility belongs to the consumer tests.

Existing source-monster definitions derive `source_policy`, `source_save_version` and `policy_version` from the current policy. Those metadata fields advance48→49. The focused comparison explicitly normalizes just those three fields before comparing the rest, including original source entries and numeric grants. It does not assert full-byte equality for newly generated actors or their current-policy provenance.

## Reproduction

Run only after the shared project import. Each test requires its own XDG_DATA_HOME under `/tmp/godot-m1-v082-source*`, with XDG_CONFIG_HOME and XDG_CACHE_HOME also temporary.

```sh
godot --headless --path . --script res://tests/source_cold_ailment_duration_test.gd
godot --headless --path . --script res://tests/source_cold_ailment_duration_migration_test.gd
```

Each command must use a fresh isolated directory when repeated. `source-data-unchanged.json` records byte equality of the source runtime JSON and normalized graph against the baseline commit.

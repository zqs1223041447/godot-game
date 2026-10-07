# v116 schema54 migration and progression boundary

## Scope and implementation

- `NormalJourneyState` now has a frozen schema50–53 four-map vocabulary and separate current five-map vocabulary/default. Schemas26–29 and30–49 retain their earlier two-/three-map paths.
- `CanonicalBuildRules.decode_v53` / `reason_v53` validate the complete old envelope before an optional caller callback. The old50–53 journey decoder/validator cannot accept `ruins_garden` progress, active identity or pending reward identity.
- `RuinsGardenMigration.migrate_v53` changes exactly the version53→54 and adds `journey.best_tiers.ruins_garden = 0`. It does not rewrite old map progress, items/locations, talents, revision, reward counters, active runs or pending rewards.
- Long Stride's historical52→53 step now validates its candidate with `reason_v53`. Earlier migration steps remain fixed at their original target versions. The default constructor and loader chain then apply53→54.
- Existing original-byte backup, concurrent-source guard, atomic write and publish-after-persistence order are reused unchanged. Successful53 migration has a map-specific message.
- Source execution policy stays49, equipment vocabulary stays51, and the frozen ordinary gem reward table stays unchanged.

## Focused results

Godot4.6.3, headless, no editor import, Main scene, combat replay or old full-suite rerun.

1. `migration-attempt01.log`: parse failure, exit1, before any test executed. One test-local inferred Dictionary required an explicit type annotation. The exact failed test is retained as `migration-attempt01-test.gd.txt`.
2. `migration-attempt02.log` and `migration-attempt02-result.json`: **575 checks, zero failures, exit0**. No production edits were made between these two attempts.

The passing run covers:

- Actual immutable v115 earned schema53 save (revision34, old-garden tierI completed, four existing shards) migrates via the real canonical loader and roundtrips without extra writes
- A separate controlled envelope for every old map's active and pending states; four distinct old best-tier values prove independent key preservation. These synthetic boundary envelopes are explicitly not earned gameplay evidence
- Exact original backup bytes, one migration write/event, no repeated54 rewrite or migration notice, and independent store reopen
- Full old-schema legality compared with pinned released53 validator source: invalid envelope, progression, currency, item identity/location, serial, group/binding, talent/source/budget and ledger data. Permissive callbacks and warmed item metadata cannot bypass native validation
- Exact old/new progress-key and numeric-tier rejection; new-map identity is rejected in all old50–53 envelopes
- Genuine historical49 active/pending fixtures passed through unchanged49→50→51→52→53 steps; actual50/51/52/53 file loaders then reach54 with one original-version backup and one write
- Real backup-failure adapter, conflicting backup, concurrent source mutation and a real `.tmp` directory blocking atomic persistence. Failed operations preserve memory, disk ownership, notifications and migration notice; removing the write fault permits one safe retry with the original backup retained
- New current map tierI–III pure start/complete/decode boundaries, waves1/4/8,24 ordinary roots, costs0/4/8, base rewards4/8/12; new progress never changes old map progress and old-garden completion cannot unlock its tierII

## Reproduce

Create fresh directories, then run from the project root:

```sh
mkdir -p /tmp/godot-m1-v116-migration-NEW/{data,config,cache}
XDG_DATA_HOME=/tmp/godot-m1-v116-migration-NEW/data \
XDG_CONFIG_HOME=/tmp/godot-m1-v116-migration-NEW/config \
XDG_CACHE_HOME=/tmp/godot-m1-v116-migration-NEW/cache \
RUINS_GARDEN_MIGRATION_REPORT=res://docs/qa/v116-ruins-garden-entry/migration-NEW-result.json \
timeout 90 godot --headless --path . --script res://tests/ruins_garden_migration_test.gd
```

The test refuses unisolated storage. Source fixture `docs/qa/v115-native-map-entry/earned-v114-save.json` is read-only and checked byte-identical after the run. Each test destination is within its fresh XDG user-data directory; normal player saves are untouched.

`migration-frozen-manifest.json` pins exact released53 Rules/Journey bytes and their base commit. At runtime only global class registrations are removed and the Rules Journey preload is redirected to the pinned four-map Journey script in isolated user storage. The rest of these two oracle sources is unchanged; other existing item/source/map dependencies are shared and retain their old identities. `migration-tested-inputs.json` records the tested production/test files, dependency and fixture hashes, retained attempt outcomes and evidence files.

## Limits

This is focused migration/progression validation, not native map admission, UI, rendered art, natural combat clearing, Windows behavior, performance or an old regression-suite pass. New-map start/completion here is a pure state boundary fixture and does not claim physically earned tier unlocks or rewards; the parent's separate entry test owns actual fee/admission integration.

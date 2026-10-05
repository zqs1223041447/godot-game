# v0.52 Shock compiler, gem and schema integration

Production scope: explicit `shock` / `support:shock` support for native `bolt`, `nova`, and `chain` primary hits, using `ShockRules.PLAYER_POLICY`; current canonical save schema31 and frozen schema30 admission. A migrated schema30 envelope changes only `version`; no item, currency, reward, UID, location, revision, binding, skill-group, talent, or journey grants/changes occur. The previous third-map migration now validates its frozen schema30 output before Shock migration runs.

The compiler emits `shock_profile` only for selected Shock support and adds exactly the four policy values to `snapshot.shock_policy`. Damage and mana factors use the existing primary modifier and final resource-cost authorities. Raw snapshots containing `shock_policy` are rejected, including empty or malformed payloads. No automatic support is enabled by lightning components, critical strikes, or independent secondary explosions.

## Released schema30 inputs

`fixtures/v30-{default,ember-bag,active,pending}.json` were captured by executing `capture_released_v51.gd` externally against `/workspace/scratch/a51485f153de/v051-reward-inventory-cost`, version0.51.0, schema30. The coordinating task identifies this released source as published commit `d6684d`. The capture used the old code's actual inventory, crafting, binding, map-start, map-completion and reward APIs and a new `/tmp/godot-m1-v052-fixture-literal30` user-data directory. No old save was opened or modified and no current-code snapshot was assigned an old version. The log's word “pack” is inherited from the prior capture script; this capture executed the released source tree, as its command and manifest state.

The captured JSON deliberately uses a leading space/CRLF and trailing whitespace. The save test requires exact byte-for-byte preservation of those originals in `.v30-backup.json`. `fixtures/manifest.json` contains the capture script, old project and all 150 old-production-script SHA256s, along with each fixture's byte length and SHA256. `v30-vocabulary-oracle.json` captures all old minimum gem save versions and 128 milestone reward ordinals for frozen-reward comparisons.

## Focused checks

- `tests/shock_support_compiler_test.gd`: all ten active skills plus basic; native-lightning admission even with equipment-added lightning and guaranteed critical; exact profile and snapshot shape; each compatible existing support pair; representative five-support groups; final mana and all primary hit components; chain bounces; unchanged secondary explosion; no-source fields; injection and detachment; real imported texture; dynamic test supplier and formal four-shard offer; actual purchase, equip rejection/acceptance and strict reload
- `tests/shock_gem_migration_test.gd`: four literal schema30 saves; full old-schema validation and injected Shock rejection; version-only transformation; unchanged identities, ordering, revisions, pending/active journey and rewards; raw original backup; conflicting backup, backup failure, external edit, real atomic-temp failure, retry, retained prior receipt; representative older chains; all 128 released reward ordinals and previous gem save minima

These checks use independent `/tmp/godot-m1-v052-*` data directories. After the coordinating task completed its clean shared import, both focused tests ran successfully: 556 compiler/catalog/model checks (18 compatible existing support pairs) and 313 migration checks, each exit0 and zero failures, with no script/parse errors. The replay command is `bash docs/qa/v052-shock-integration/run-focused.sh`. Its final run used `/tmp/godot-m1-v052-integration.T0cQmV`; `final-evidence.json` records the exact per-test exits, log hashes and production/test source SHA256s. No full historical or 600-second suite is part of this scope.

## Correction and scope

The first compiler attempt failed because its fixture added a new `attack.lightning` dictionary key with dot syntax, yielding a `StringName` that the existing strict typed-damage decoder correctly rejected. The initial log and a diagnostic rerun are preserved in `shock_support_compiler-attempt{1,2}.log`, with matching source hashes in `attempt{1,2}-evidence.json`. The fixture now inserts literal String keys with `merge`; no production change was needed. The final run passed all 869 checks. This is not a claim that the first run passed.

The final status roles match the actual packet recipes: `bolt → projectile`, `nova → direct`, `chain → bounce`. The test verifies each emitted primary packet role against its profile. Runtime settlement, combat/visual acceptance and the overall release gate remain separate coordinated work.

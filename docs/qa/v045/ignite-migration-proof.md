# Ignite gem schema28 migration

Schema28 opens exactly `support:ignite` at level1, quality0. `GemCatalog.minimum_save_version()` returns28 for that ID; every released old ID retains its previous minimum. Equipment vocabulary remains27 and source passive execution remains25. No equipment roll, passive word, stat, wallet, currency price, journey field or initial gem grant changes in this migration.

`Rules.decode_v27()` and `Rules.reason_v27()` reuse the existing strict generic validators with expected version27. `IgniteGemMigration.migrate_v27()` validates that frozen envelope before copying it and changing only its version to28. A schema27 file carrying the new ID in either a bag or skill link is rejected before any backup or migration write, even after a schema28 validation has warmed current metadata caches. The schema26 equipment step remains pinned to `reason_v27()` and the schema25 journey step remains pinned to26. Loading older supported versions uses their existing chain and adds the27→28 step once. The legacy schema14 itemization step also filters its automatic support grants by the frozen minimum version before allocating UIDs, keeping the old16 grants and excluding ignite.

The store keeps its existing backup, atomic primary-write and disk-receipt mechanisms. Only the source version's original raw bytes are backed up. The primary write and in-memory acceptance happen after old-envelope validation and successful backup. Backup conflicts, failed primary writes and external mutations preserve their existing rejection and retry behavior.

## Independent released fixtures

`ignite-migration-capture.gd` ran externally against the retained released v44 `game.pck`, without importing or loading the changed source tree. It checked application version0.44.0 and schema27 before using the released game's normal map, XP, reward, binding, equipment and crafting APIs. It emitted three literal raw JSON files with CRLF and surrounding whitespace:

- `v27-default.json`: untouched released default profile
- `v27-active.json`: paid tier2 active map, modified bindings, real equipment/crafting, level4 XP6, 90 root kills and unclaimed gem milestone
- `v27-pending.json`: the same released profile with the tier2 map complete and its reward still pending

The same old pack generated `v27-vocabulary-oracle.json`: its exact26 gem definitions,128 deterministic gem milestones and minimum save version for every old gem. The manifest records byte lengths, SHA-256 values, capture source and isolated data paths. Source release commit: `64480de39e2fb84279e58b25ec21add549dd1bdd`. PCK SHA-256: `e0611f64aca665e4b2fe37d6bde54f56a3a633f0b7124f4ba9e98f2527d0fc0f`.

`NormalJourneyState` remains byte-identical to the baseline source, SHA-256 `10b2ba7db25764a0ad34f447ed71acb4a876a49e26bd6fa824056d1e1fee0f89`.

## Focused validation

`tests/ignite_gem_migration_test.gd` covers:

- Every preserved field, UID, item payload, location, skill group, binding, progress, talent, crafting revision, ledger and normal journey value; only version27 becomes28
- Literal raw backup bytes, single migration write, unchanged current reread, independent reopen, exact accepted disk receipt and absence of a leftover primary temporary file
- Known new ID injection in old27 bag and link, old25/26 rejection, warmed-cache rejection and custom-talent-validator rejection
- Valid schema28 gem instances, malformed old/current payloads, direct float payload rejection, malformed or aliased IDs, StringName identity rejection and unexpected payload fields
- Backup conflicts, backup failure, primary failure/retry, external changes during backup, real atomic temporary-file collision, subsequent receipt conflict and preservation of a previously loaded receipt after migration failure
- Minimal literal old25 and old26 fixture chains ending at28 in one write with only the original-version backup
- Frozen26 reward list,128 old milestone outputs, all old gem minimum versions, no initial ignite gift, unchanged trade prices and a dynamic27-entry trade catalog
- Accurate old27 migration text describing availability without claiming a grant

The first focused run exposed the legacy itemization step enumerating the expanded current support catalog, which gifted ignite into schema14 and broke the default chain. Its original stdout is retained in `ignite-migration-first-default-gift.log.txt`; that run is a failure despite its printed check count, because script assertions are failures. The narrow schema14 gift filter fixes the cause. The final focused execution passed with462 checks,0 failures, exit0 and no script errors/assertions, recorded in `ignite-migration-test.log.txt`. Source/asset hashes and the isolated command are recorded in `ignite-migration-tested-files.json`. No historical full-suite or600-second run is part of this focused check.

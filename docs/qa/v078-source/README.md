# v0.78 source policy48 and schema48 validation

Validated on Godot 4.6.3 using the parent's single shared import. No additional import, export, historical suite or long gameplay run was performed here.

- `source-corrected.log.txt`: 10,799 checks, zero failures
- `migration.log.txt`: 120 checks, zero failures
- `consumer-checks.json`: 12 actual production text anchors verified for source aggregation, frozen snapshots, packets and damage settlement
- `tested-input-sha256.json`: exact tested source, helper, native47 fixture and pinned data hashes
- `frozen-source-provenance.json`: independent pre-change runtime/parser from commit07922581, with only class-name removal and the frozen parser preload redirect

`source-initial.log.txt` retains the first attempt: 10,753 checks and two test-assumption failures. Both failures assumed two fully reachable Cold/Lightning groups. The approved source expansion provides one reachable group of each type. The corrected test explicitly checks those sole gateways and tests cross-entrance uniqueness using already-supported Fire groups. Production code did not change after that first execution. The source test had no section selector, so its corrected script ran once more; the passing migration script was not repeated.

## Exact source boundary

Only these four original lines open at source policy48:

- Cold Mastery4116: `40% of Physical Damage Converted to Cold Damage`
- Lightning Mastery53046: `40% of Physical Damage Converted to Lightning Damage`
- Heart of Ice8833: `Damage Penetrates 6% Cold Resistance`
- Heart of Thunder56716: `Damage Penetrates 6% Lightning Resistance`

Both original30% increased-damage notable lines remain. Current-node/choice comparison against the frozen runtime changes exactly13 records: two notables, six Cold Mastery entrances and five Lightning Mastery entrances. Every node and every mastery option retains its original result under explicit save47; execution-policy boundaries14–47 also match the frozen implementation. Conditional, weapon-specific, extra-damage, Avatar and variant-quantity text stays closed. Source JSON, node IDs, topology and Chinese dictionaries are unchanged.

Only60170/4116 and58816/53046 have currently supported paths from the shared Witch route. Other entrances can display the supported effect but their groups retain unsupported prerequisites.

## One shared lawful fixture

`tests/fixtures/v078/elemental_conversion_fixture.gd` provides `prepare(game,path,selected)` and `select(game,path,selected)` for source, Main and F8 checks. It preserves owned items and establishes an explicit level23 fixture with class3 and27 earned points, then spends all paid points through actual model transactions. It creates no new equipment samples.

The normal route has25 nodes including one free class root:24 paid ordinary points. Fire34927/65020, Cold60170/4116 and Lightning58816/53046 add three mastery points. All three together spend27 with zero remaining.

- `fixtures/zero.json` has no conversion mastery, three unspent points and both6% penetration notables
- `fixtures/selected.json` has all three conversion masteries, both6% penetration notables and zero unspent points

The zero-mastery fixture is not a no-penetration baseline. Actual allocation, every single/pair/triple choice, reload, refunds, repeated selections, existing cross-entrance uniqueness and a real `.tmp` filesystem failure are tested. The no-allocation built-in fixture carries no new optional stats.

## Persistence boundary

The genuine released schema47 input is `docs/qa/v073-gameplay/fixtures/selected.json`; this is read as its original bytes. Frozen47 decoding and full native validation run before any optional callback or schema48 migration. New source allocations cannot be preinserted into47, including with a permissive callback.

Migration changes only `version`. Equipment vocabulary remains46. Items, locations, serial, points, revision, ledger and journey remain unchanged; it grants no items, currency or points. Direct47 and existing45/46 loader chains produce one atomic48 write with the exact original-version byte backup. The full built-in legacy chain remains constructible because the prior Frost Lock migration now explicitly validates its fixed47 output. Current48 reload and disk stamps remain read-only.

Malformed native envelopes, backup failure, existing conflicting backup, concurrent external mutation and actual atomic-write failure preserve the old bytes/live state as applicable. After removing the atomic fault, the same migration succeeds once.

SourceMonsterGrants derives its current source-policy metadata and cache key from SourceTreeRuntime.CURRENT_SAVE_VERSION, now48. Its existing five source entries and numeric grants remain unchanged; newly created identities carry policy48. Existing actor snapshots stay frozen. This work does not claim full-byte equality of newly generated monster objects across that declared metadata change.

## Commands

Each script used an isolated `/tmp/godot-m1-v078-source-*` XDG tree and the already imported shared project:

```
XDG_DATA_HOME=/tmp/godot-m1-v078-source-corrected \
XDG_CONFIG_HOME=/tmp/godot-m1-v078-source-corrected/config \
XDG_CACHE_HOME=/tmp/godot-m1-v078-source-corrected/cache \
/usr/local/bin/godot --headless --path . --script res://tests/elemental_conversion_source_test.gd

XDG_DATA_HOME=/tmp/godot-m1-v078-source-migration \
XDG_CONFIG_HOME=/tmp/godot-m1-v078-source-migration/config \
XDG_CACHE_HOME=/tmp/godot-m1-v078-source-migration/cache \
/usr/local/bin/godot --headless --path . --script res://tests/elemental_conversion_migration_test.gd
```

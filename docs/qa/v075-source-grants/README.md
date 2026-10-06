# v075 source Damage/Life admission checks

The adapter admits exactly three source IDs, in this order:

- `source_gale_stride`: source `63417`, index `1`; existing v74 movement increase
- `source_ember_power`: source `13219`, index `0`; current `10% increased Damage`
- `source_grove_vitality`: source `52282`, index `0`; current `5% increased maximum Life`

Every value comes from the current `SourceTreeRuntime.line_effect` parser. The
adapter's per-ID policy checks node/index and exactly one finite, nonnegative
scalar grant with the approved stat and `increased` mode. There is no copied
numeric value or role coefficient in the production admission policy. Sibling
evasion, shield, and Transfiguration of Body clauses are not admitted; source
node allocation, ascendancy and full-node execution remain separate concerns.

`IDS` and `owns(id)` provide an exact admission boundary for Registry consumers.
`resolve(id)` retains `{ok, reason, stats, definition}`. Damage uses
`stats.global_increased`; Life has empty `stats` and carries
`capacity_increased.max_health` in both the result and definition. The two new
definitions also retain the parser's unscaled `typed_grants` array, including
its mode. The Gale result/definition retains its complete v74 serialized shape
without empty capacity or typed-grant fields. Public returns are fully detached.

The static cache contains at most one validated entry per admitted ID, bounded
to three total. Every lookup first reads the compact current source entry;
actual metadata, raw line, execution policy and save version form its identity.
Alternating IDs reuse independent entries. A failure removes that ID's prior
entry and has no fallback; unrelated cache entries remain intact and are still
revalidated against their own current source identity on their next lookup.
Source-tree Runtime stays lazy-loaded to avoid the Registry/jewel preload cycle.

The existing adapter suite was updated only for per-ID private cache inspection.
The new suite checks:

- Full serialized Gale result and definition equality against a frozen v74
  construction from `f2427f3`, before and after the new-source checks
- Exact current source/parser equality, complete provenance, raw typed modes,
  and Life capacity routing without a flat Life grant
- Malformed parser outputs, extra or wrong stat/mode/condition fields, multiple
  grants, invalid scalar types, negative/nonfinite values, and missing identity
- Unknown IDs, different approved node substitutions, source failures,
  unsupported/compound/conditional lines, and no stale result reuse
- Independent hits across 100 alternating three-ID cycles, the three-entry
  bound, metadata/line/policy/save-version invalidation, and source restoration
- Nested output mutation isolation, including `typed_grants`, provenance and
  `capacity_increased`

After the parent performs the single shared Godot import, run:

```sh
python3 docs/qa/v075-source-grants/run-focused.py
```

The runner executes only `tests/source_monster_grants_test.gd` and
`tests/source_damage_life_grants_test.gd`, with isolated Linux XDG directories.
It writes the exact commands, logs, exit codes and transitive input hashes
before/after execution. It neither imports the project nor reruns the unchanged
16,955-check SourceTreeData suite. Registry scaling and live spawn consumers
have separate integration coverage.

## Results

The parent completed the shared import before these runs (14.361 seconds,
exit 0, no error lines). Focused execution used Godot 4.6.3 stable.

- `source_damage_life_grants_test.gd`: **234 checks, 0 failures**, first run,
  exit 0; see
  [raw log](20261006T084830.968763Z-source_damage_life_grants_test.log.txt) and
  [first-batch receipt](20261006T084830.968763Z-receipt.json)
- `source_monster_grants_test.gd`: **79 checks, 0 failures**, exit 0; see
  [raw log](20261006T084913.323439Z-source_monster_grants_test.log.txt) and
  [targeted retry receipt](20261006T084913.323439Z-receipt.json)

The first batch's old Gale suite failed before execution because GDScript could
not infer `first_key` after the test switched from a typed cache variable to a
Dictionary lookup. The [initial failure log](20261006T084830.968763Z-source_monster_grants_test.log.txt)
is retained. Adding an explicit `PackedByteArray` annotation fixed that test.
The production adapter was unchanged. Only the failed old suite was retried:

```sh
python3 docs/qa/v075-source-grants/run-focused.py tests/source_monster_grants_test.gd
```

Both receipts confirm unchanged transitive inputs during their respective runs.
The initial batch receipt is intentionally marked failed because of the old
suite's parse error; the new suite passed in that same batch and was not rerun.
No SourceTreeData, full-history, UI, or spawn-consumer suite was run here.

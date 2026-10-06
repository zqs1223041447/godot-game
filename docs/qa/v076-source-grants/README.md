# v0.76 source shield grant boundary

The shared source adapter admits two additional exact source mechanisms. It
reads compact entries from the existing `SourceTreeData` cache and obtains every
numeric value from the current player `SourceTreeRuntime.line_effect` parser.

- `source_aegis_capacity` / 辉壁储盾: `58218:0`, `8% increased maximum Energy
  Shield`, delivered as `capacity_increased.max_shield` with value `0.08`
- `source_aegis_recovery` / 辉壁复苏: one atomic pair, in order: `21929:1`, `4%
  increased maximum Energy Shield`, and `6949:1`, `10% increased Energy Shield
  Recharge Rate`. The channels are `capacity_increased.max_shield = 0.04` and
  `stats.shield_recharge_rate_increased = 0.10`

These are parser-derived increased values. The adapter contains no monster
supply conversion, base recharge rate, faster-start grant, sibling-node grant,
node allocation, or scaled actor cache.

## API and authority

The original three source IDs retain their entire definition and resolve byte
shape. The new capacity ID follows the existing single-entry capacity shape.
Recovery returns the normal `ok`, `reason`, `stats`, and `definition` fields,
plus `capacity_increased`.

Recovery's definition stores both compact entries in `source_refs` and
`source_entries`, both raw parser grants in `typed_grants` in the same entry
order, and both source lines joined by a newline in `source_line`.
`source_entry` is retained for presentation compatibility and explicitly marked
with `source_entry_scope: first_entry_only`; it is not the whole authority.
All returned nested collections are detached from the validated cache.

`_definition_for` and `_entry_key` keep their existing single-entry behavior.
`_bundle_definition_for(entries, policy, save_version, parsed_results, id)` is
the pure atomic validation boundary, with Recovery as the default ID.
`_bundle_key(entries, policy, save_version)` serializes both entire compact
entries, including actual source version/hash/commit/URL and raw lines, plus
execution policy and save version.

There is at most one cached definition per exact ID, five total. Failure in
either Recovery entry rejects the whole result and evicts only Recovery. The
adapter validates matching source generations across the pair and never
returns a stale capacity or rate half. Runtime loading remains lazy to avoid
the registry dependency cycle.

## Focused validation

Passed on Godot 4.6.3: **381 checks, 0 failures**, exit 0, no engine/script
errors, in 0.994 seconds. The project validation runner isolated Linux XDG
settings, caches, and save paths. Inputs were hashed before execution and
verified unchanged afterward.

```sh
bash tools/validate.sh res://tests/source_shield_grants_test.gd
```

- [Run log](20261006T092349.548389Z-source_shield_grants_test.log.txt)
- [Result and input hashes](20261006T092349.548389Z-source_shield_grants_test.result.json)

`tests/source_shield_grants_test.gd` covers current source/parser equivalence,
both-entry atomic rejection, malformed parser grants and source metadata,
mixed source generations, changes to every cache identity field, zero and
overflow source lines, detached returns, five independent bounded cache
entries, source-state read-only behavior, no global RNG consumption, and full
legacy resolve/definition byte equivalence.

The old adapter fixture, `source_monster_grants.v075.gd.txt`, is the exact
unmodified output of:

```sh
git show 76c9cab:scripts/mechanics/source_monster_grants.gd
```

Its SHA-256 is
`edc5f27ffeac782484e763c1ea87ce0d0935238029fe76f7883b79f5d36c04a5`.
The focused test strips only its global class registration in memory to load
the frozen implementation alongside the current implementation; it compares
all three old IDs using complete `var_to_bytes` results.

The unchanged full SourceTreeData suite is not repeated. Monster supply,
factory snapshots, encounter policy, gameplay and UI checks belong to their
separate v0.76 validation evidence.

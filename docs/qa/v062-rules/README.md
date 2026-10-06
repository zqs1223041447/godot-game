# v062 armour / evasion affix rules

The focused pure-rules batch passed on its first execution with Godot 4.6.3:
13,913 checks, zero failures, 1,098 historical item/post-RNG comparisons, and
2,846 historical Craft plan comparisons. The original output is preserved in
`run-01.log.txt`; machine-readable counts and actual roll witnesses are in
`results.json`. No full historical test suite or gameplay/UI runner was invoked
by this batch.

## Run

From the project root, after the coordinated shared import:

```sh
DEFENSE_RATING_REPORT=docs/qa/v062-rules/results.json \
XDG_DATA_HOME=/tmp/godot-m1-v062-rules-data \
XDG_CONFIG_HOME=/tmp/godot-m1-v062-rules-config \
XDG_CACHE_HOME=/tmp/godot-m1-v062-rules-cache \
/usr/local/bin/godot --headless --path . \
  --script tests/defense_rating_affix_rules_test.gd
```

## Evidence

- Exactly two new flat prefixes on the existing `emberhide_vest`, with integer
  endpoint/gate checks at item levels 1, 7, 8, 15, 16, and 30
- Every other base rejects them; duplicate families/groups, invalid tick types,
  out-of-range values, four prefixes, and four suffixes reject
- All ten choices of three from the five eligible prefixes validate at the
  unchanged rare 3-prefix / 3-suffix cap; magic remains 1 / 1
- Actual `get_stats` and `definition` yield float armour 120.0 / evasion 450.0,
  and format `护甲 +120` / `闪避值 +450` without percent division
- Actual defense and attack-admission consumers accept those rating points
- Natural generation reaches both new families, all tiers, every rarity count,
  and a six-affix item with both prefixes; current weighted dispatch is checked
- Salvage and recalibration retain their exact formulas; enchant, elevate,
  augment, reforge, and targeted damage reforge reach both new families without
  changing their prices or global RNG. Retained prefixes preserve exact ticks
- Historical `defense`, `defense_v37`, every old ordered pool and loot profile,
  old adapters, and explicit vocabulary 1..38 preserve typed result bytes
- Vocabulary 37 retains the literal `defense_v37`; explicit 35/36/38 remain
  rejected. Seed namespaces, quotes, and full Craft envelopes remain unchanged

## Independent historical oracle

`frozen/manifest.json` pins published v61 commit
`d884caea7a2260f4535ba4da2d7e005e6df006d4` and records SHA-256 hashes for every
original and relocated file. The eleven-file recursive preload closure includes
the catalog, both Craft implementations, targeted reforge, all profile modules,
weapon-local rules, defense rules, and damage resolver.

Only `class_name` declarations were removed and references into the closure
were relocated. The oracle preloads no production implementation. Its source
and transformed hashes were checked against the pinned Git object before the
batch. Comparisons use `var_to_bytes`, preserving numeric types, ordered array
contents, dictionary order, and signed 64-bit RNG states. JSON is used only for
the human-readable report, not as the equality oracle.

Production changes are limited to the new profile and versioned catalog
registration/dispatch. Existing crafting source needed no changes. Save,
SourceTree aggregation, actual-main behavior, and UI/export checks are owned by
the separate v062 integration batches.

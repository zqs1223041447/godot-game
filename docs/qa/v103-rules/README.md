# v103 resistance targeted reforge rules

Current follow-up: [original-hash dependency isolation](../equipment-consistency/README.md) repairs later shared-dependency drift without changing this historical manifest, sources or recorded results. The evidence below remains the original v103 scope.

The focused contract passes using the final affected rerun and unchanged evidence
from the initial run. No production defect or production edit was needed in this
QA batch. This is a pure-rules check, not a model transaction or UI check.

- Final current + historical matrix: **17,944 checks, 0 failures**
- Current scope: all **15 bases**, magic/rare, item levels **1/8/16/30**;
  **480 quotes** and **448 successful plans** over eight representative signed seeds
- Historical gates: **40 quotes + 40 plans** across vocabulary 34/37/39/46/51
- Original four targets: **96 quote + 768 plan comparisons**, each checked both
  directly against frozen TargetedReforgeRules and through the Craft envelope
- Original six operations: **24 quote + 192 plan comparisons**, with literal old
  seed namespaces checked at current vocabulary and vocabulary26

`results.json` records the evidence sources and test hash. The original four and
six comparisons passed on the first run and were not repeated after unrelated
test-only changes. All byte comparisons use `var_to_bytes`, never JSON equality.

## What is verified

1. Exactly four target IDs are appended after the original four, without changing
   original target metadata, order, fee, rules namespace, or existing planner
2. Fire/cold/lightning target only `emberhide_vest` or
   `nine_slot_etched_ring`; chaos targets only the ring. Every other current base
   rejects before seed validation, without a roll, debit, or partial result
3. Both supported rarities work from item level1. The existing tiers remain
   level1: 8–12 ticks / weight100; level8: 13–18 / weight60; level16: 19–25 /
   weight30. Pool checks verify gates, weights, bounds and family eligibility
4. Magic costs16 calibration shards and yields1–2 affixes with at most1 prefix
   and1 suffix. Rare costs40 and yields4–6 with at most3 prefixes and3 suffixes.
   No duplicate family/group or out-of-vocabulary entry survives validation
5. At least one legal resistance family is guaranteed. Identical seeds give
   byte-identical entire results even when the legal source's old affixes differ:
   this replaces the entire affix set. ID, base, rarity and item level are preserved
6. Invalid operation/instance/seed/version inputs reject. Source bytes remain
   unchanged, and mutating metadata, quote costs/counts, result affixes, derived
   stats or result costs never changes later calls
7. Actual `Catalog.definition` and `Catalog.get_stats` compute resistance as
   base resistance plus integer percent ticks divided by100. The real
   `maximum_*_resistance_add` consumer keys are absent, so these targets grant
   no maximum resistance
8. Historical armor cold/lightning begin at vocabulary37; ring elemental
   resistance begins at46 and chaos at51. Historical source legality is also
   enforced, including rejection of a chaos-bearing item under vocabulary46
9. Quotes and plans leave Godot's global RNG untouched. Plans own a local seeded
   RNG. External transaction RNG/payment/save ownership is covered separately
   by the model suite, not claimed by this pure suite

## Actual generated gear

`generated-gear-witnesses.json` contains 14 actual before/after records: magic and
rare examples for all seven legal base/target pairs at item level30, plan seed0.
Each record includes the real source, full result/definition, generation pool,
local generation seed and candidate number. Every source came from
`Catalog.generate_for_pool`; the rare sources have five legal affixes and the
recorded rare results have six. No handcrafted three-affix rare was used as a
success fixture. The intentional three-affix rare rejection case is malformed
only to test validation.

JSON is a portable report, not the byte-comparison oracle. Consumers recreating
fixtures should use the recorded generation method/seed and preserve the
catalog's integer payload types.

## Preserved first failure and focused reruns

The initial run had **20,267 checks and one test-assertion failure**. Its eight
fixed seeds happened to select T1 and T3 at level30; the assertion incorrectly
required that small weighted sample to visit all three tiers. All production
contract checks and historical differential comparisons passed. The assertion
now tests the actual promise: a high item level can still yield a low tier.
Tier2 availability is checked directly in the level8 and higher target pools.

- `run-01.log.txt` / `results-run-01.json`: untouched first failure evidence
- `run-02-current-matrix.log.txt`: corrected current matrix, 17,251 checks,0 failures
- `run-03-current-and-historical.log.txt`: final matrix with the actual maximum
  resistance consumer key checked, 17,944 checks,0 failures

The final maximum-resistance assertion was strengthened after examining the
consumer's actual key. Only the affected current and historical result matrices
were repeated. No editor import, full historical sweep, soak, or unrelated UI
runner was invoked.

## Frozen oracle

`frozen/manifest.json` pins
`b7d98c5b94c2c39f6f258835b28cfc32c4cd34d9`, with source and transformed SHA-256
hashes. `TargetedReforgeRules` is the exact Git source with only its `class_name`
removed. `CraftingRules` also removes `class_name` and redirects its Targeted
preload to that frozen file. Both transformed files were independently checked
against the pinned Git object.

The 13 shared preload dependencies, including the real catalog, all family
profiles, CraftingExpansionRules, and defense/local-weapon mechanics, are
byte-identical to b7 and guarded by their SHA-256 on each run. Production
CraftingRules itself is also hash-guarded as unchanged. Thus these are frozen
rule implementations over unchanged catalog dependencies, not a separately
frozen copy of the entire engine or project.

## Reproduce

After the coordinated dependency parse (no editor import required), from the
project root:

```sh
XDG_DATA_HOME=/tmp/godot-m1-v103-rules/data \
XDG_CONFIG_HOME=/tmp/godot-m1-v103-rules/config \
XDG_CACHE_HOME=/tmp/godot-m1-v103-rules/cache \
V103_RESISTANCE_RULES_REPORT=/tmp/godot-m1-v103-rules/full-results.json \
/usr/local/bin/godot --headless --path . \
  --script tests/resistance_targeted_reforge_test.gd
```

For only the changed matrix, add
`V103_RESISTANCE_RULES_SCOPE=current_and_historical`. The recorded runs used
Godot4.6.3 and isolated `/tmp/godot-m1-v103-*` XDG directories.

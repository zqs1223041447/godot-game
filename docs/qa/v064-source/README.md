# v64 Iron Reflexes source and pure rules

The focused test passed **7,045 checks, zero failures in 2.533 seconds** on Godot 4.6.3. See `results.json`, `focused.log.txt`, and `execution-receipt.json`.

## Independent baseline

`freeze_oracle.py` reads Git commit `76e2abccf533cd31c20daea92c0e05b02c0980af` (published v63). The frozen oracle is the complete nine-script SourceTree preload closure, totaling 97,517 original bytes. It removes only global `class_name` declarations and rewrites every recursive preload to the frozen directory. It loads no current production script. The unchanged source-tree and passive-balance JSON inputs are separately SHA-256 pinned. No project, asset, save, or engine import cache was copied.

Run `python3 docs/qa/v064-source/freeze_oracle.py --verify` to compare all frozen files with the original Git objects. v63 used save version 39 and source execution policy 38; the independent oracle retains that distinction.

## Proven scope

- All 2,387 standard node effect records and 1,837 mastery choices retain their complete typed result bytes except the new complete `10661` entry. Full standard nodes increase from 770 to 771; no mastery opens
- Exactly the original complete sentence grants one `iron_reflexes=1` flag. Old versions 14–39, near matches, split clauses, conditionals, malformed values, and disabled parser gates reject it
- Every class can reach `10661` using previously full nodes. Point counts in class order are `[17,15,13,27,12,22,19]`. The shortest route is Duelist, 12 points, minimum level 8. `results.json` records every exact path
- A real connected path to mixed node `53002` passes graph/budget legality, but source admission and availability reject its unimplemented Onslaught effect. Other partial and conditional defense nodes remain closed
- The helper checks `A0*(1+IA) + E0*(1+IA+IE-H)`, where H is only a shared increase from the same original source entry. It rejects negative/non-finite input, impossible H, and overflow; zero, fractional, and large finite inputs remain valid
- Ten source compositions distinguish one/two/three repeated real 6% hybrid nodes, same-valued independent 8% Armour/Evasion entries, repeated independent sources, 14% single-stat entries, and their combinations. Other source lines, including hybrid nodes' life increases, stay active
- A legal four-affix vest supplies flat armour 120 and evasion 450. On the real Duelist route, the authored 15 base evasion makes converted armour 465 and total armour 585, with zero evasion. Dexterity remains 123 and accuracy remains 371. Without the keystone evasion remains 576.6; adding more Dexterity increases accuracy without increasing converted armour
- 64 complete `apply_stats` output vectors match frozen v63 byte-for-byte when `10661` is absent: 42 legal start/path variants, 21 pure composition variants, and one existing jewel accumulation vector. These comparisons include numeric types, key order, and the absence of both new active-only keys. The pure composition/jewel vectors exercise aggregation directly; they do not claim allocation legality
- The complete existing Chinese Iron Reflexes text loses its unsupported marker together. Mixed nodes preserve supported-line rendering and unsupported-line markers; the consumer manifest names actual executable code

The test creates no scene, save, combat simulation, item roll, or import. Save migration, runtime gameplay, and presentation are covered by their separate v64 focused tests.

## Reproduction

After the project's coordinated import, run from the repository root:

```sh
python3 docs/qa/v064-source/freeze_oracle.py --verify
XDG_DATA_HOME="$(mktemp -d /tmp/godot-m1-v064-source-XXXXXX)" \
XDG_CACHE_HOME="$(mktemp -d /tmp/godot-m1-v064-source-cache-XXXXXX)" \
V064_SOURCE_REPORT="$PWD/docs/qa/v064-source/results.json" \
godot --headless --path "$PWD" --script res://tests/iron_reflexes_source_test.gd
```

The first run exposed two test-fixture issues: byte-comparing typed and untyped array literals, and using a rare vest with fewer than its required four affixes. Those fixtures were corrected, the connected partial-node rejection was strengthened, and the complete focused test then passed. The initial log and execution receipt are preserved as `attempt-01.*`; neither issue required a production change. `tested-input-sha256.json` records the final test and its current production script dependencies.

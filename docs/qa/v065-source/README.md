# v65 Zealot's Oath source and pure rules

The focused test passed **9,428 checks, zero failures in 2.908 seconds**, first run, on Godot 4.6.3. See `results.json`, `focused.log.txt`, and `execution-receipt.json`. Production and test input hashes stayed unchanged throughout the run.

## Independent v64 baseline

`freeze_oracle.py` reads published v64 commit `23983fe8138e591d2b1af6892b7df13a918dd19d`. The independent oracle is the complete ten-script SourceTree preload closure, including the v64 Iron Reflexes helper, totaling 101,050 original bytes. The only transformations remove global `class_name` declarations and redirect every recursive preload/load to `frozen/`. The oracle loads no current production scripts. The unchanged source-tree and passive-balance JSON inputs are separately SHA-256 pinned. No project, asset, save, or import cache was copied.

`python3 docs/qa/v065-source/freeze_oracle.py --verify` compares every frozen byte with the original Git objects. This oracle preserves v64 source policy40 and its older save39/source38 distinction; it is not the earlier v63/source38 baseline.

## Proven scope

- All 2,387 standard node effects preserve their complete typed output bytes except the new complete `63425` entry. Fully implemented standard nodes increase from 771 to 772. All 1,837 mastery choices preserve their typed output bytes. Both save39 and save40 node effects match their respective frozen v64 outputs
- Only the exact original sentence `Life Regeneration is applied to Energy Shield instead` grants the single `zealots_oath=1` flag. Versions14–40, the disabled new gate, disabled prerequisite gates, malformed values, case/whitespace/punctuation variants, incomplete sentences, appended conditions and multiline combinations reject it. Interleaved policy caches and caller mutation are covered
- Every class reaches `63425` through otherwise implemented nodes. Point counts in class order are `[15,16,26,11,22,11,19]`: Scion15, Marauder16, Ranger26, Witch11, Duelist22, Templar11, Shadow19. Witch and Templar have the cheapest witnessed routes, 11 points/minimum level7. All seven exact paths pass full allocation legality and are recorded in `results.json`. Opening the keystone adds no downstream nodes
- A real connected Templar path to Soul Thief `32176` passes graph and point-budget legality, but complete-source admission and availability reject its unimplemented energy-shield recovery-on-kill line. Five mixed shield/recovery nodes remain partial and unavailable
- The pure helper computes `life_rate=0.0`, `shield_rate=R+P*S`, where R is raw flat life regeneration, P is the raw decimal fraction, and S is final maximum shield. Zero inputs, flat-only, percent-only, combined, fractional, and large representable values pass. Each negative/non-finite input and finite-input multiplication/addition overflow rejects. A zero maximum shield still compiles a positive flat rate; actual recovery remains the gameplay consumer's responsibility to clamp
- Ten composition vectors cover raw flat/percent inputs, zero regeneration, real Robust `31033` (flat10 plus1.2%), independent `32482` (0.6%), `38906` (4% maximum shield plus its unchanged10% armour), and `19374` (flat10 shield plus4% maximum shield). Each component is added once. Source order preserves the converted rate, and inputs remain untouched
- For a Witch with raw shield200, base Intelligence32 and `31033+32482+38906`, final shield is214 and shield regeneration is13.852/s. Life regeneration becomes0.0. The previous life-scaled28.126/s value is not reused. Changing life capacity or Strength does not change the conversion; rounded aggregate Intelligence and shield capacity change the percentage contribution exactly once. Raw shield400 gives final428 and17.704/s; raw shield0 retains flat10/s as a compiled rate
- Active conversion changes only `life_regen` and the two explicit active-only fields `zealots_oath` and `shield_regeneration_rate`. Full typed comparison confirms every other field remains unchanged, including sentinel flask, leech and recharge data. This is source-stat evidence; the separate gameplay test verifies actual resource recovery
- 67 complete `apply_stats` vectors match the frozen v64 oracle byte-for-byte, including numeric types and key order: 63 class/path/input vectors, two direct old-policy attempts containing the new node, one active Iron Reflexes vector and one existing jewel-aggregation vector. Unallocated output gains neither new field. Aggregation-only source/jewel vectors do not claim graph legality
- Life/energy-shield Regeneration Rate, general Life Recovery Rate, direct shield regeneration and conditional life regeneration remain unsupported. Existing shield recharge stays separate
- The existing Chinese node name is preserved. The corrected line says life regeneration applies to energy shield, its dynamic unsupported marker disappears, and every declared consumer code snippet exists. Supported and unsupported lines on mixed nodes retain their respective dynamic markers

No scene, save, combat simulation, item roll, or import was created by this test. Save migration, actual regeneration timing/resource interactions and presentation belong to the separate v65 tests. This is focused evidence, not a claim that unrelated historical suites ran.

## Reproduction

After the project's coordinated import, run from the repository root:

```sh
python3 docs/qa/v065-source/run-focused.py
```

The runner first verifies the frozen Git oracle, hashes the source/test/translation/consumer inputs, creates isolated `/tmp/godot-m1-v065-source-*` XDG data and cache directories, executes only `tests/zealots_oath_source_test.gd`, captures the result and log, and checks that input hashes stayed unchanged. It fails on a nonzero exit, a Godot script/error log, or an input change during the run.

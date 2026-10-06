# v0.72 glove/ring equipment rules

The focused pure rules check passed on Godot 4.6.3: **5,317 checks, zero failures**, including 81 historical item/result-RNG comparisons and 664 historical Craft plan comparisons. See `glove-ring-rules.log` and `glove-ring-rules.json` for the checked result and reproducible natural-roll witnesses.

Run only this batch, after the shared project import:

```sh
GLOVE_RING_REPORT="$PWD/docs/qa/v072-rules/glove-ring-rules.json" \
  bash tools/validate.sh res://tests/glove_ring_affix_rules_test.gd
```

Coverage includes the four new families, all six level boundaries, all twelve family-tier natural witnesses, strict malformed payload rejection, full three-prefix/three-resistance ring legality, flat accuracy through the existing SourceTree formula, ordinary resistance through the existing 75% cap, existing Craft costs and guarantees, and unchanged global RNG. Historical metadata, ordered pool/loot profiles, every prior explicit vocabulary including rejected 35/36/38/40–45, and unaffected current bases are compared with the baseline.

The oracle in `tests/fixtures/glove_ring_v46_frozen/` comes from `bf794d05`. Its four entrypoints retain their original code except for removing `class_name` and redirecting their mutual preloads into that fixture directory. Shared unchanged authority files are checked against their baseline SHA-256 hashes in `provenance.json`, so a changed authority cannot silently alter the oracle.

This is a bounded pure equipment/Craft check. It does not claim save migration, Main integration, UI, Windows, export, or long-running simulation verification; those belong to separate batch evidence.

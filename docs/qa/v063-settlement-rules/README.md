# Narrow ordinary-monster burn settlement candidate

This is one performance candidate against published v62 commit
`b93018005413444ad6f988974f4ef3ea09902c5e`, not a release or gameplay-performance
claim. Only `DefenseRules.incoming_burn` receives a fast receipt constructor,
for `actor == "monster"` with numeric-zero mana ratio and maximum-fire bonus.
Raw burn and fire-profile validation remain authoritative. Resource validation
still precedes receipt construction. Other actors/options and public
`settle_resolved` keep their original paths. Ordinary nonburn hits incur no new
helper call or branch.

## Result and evidence

The final focused pure batch passed with Godot 4.6.3: **58,593 checks, zero
failures**, including **58,546 complete `var_to_bytes` comparisons** with the
independent published-v62 oracle. See `run-03.log.txt` and `results.json`.
The comparison preserves dictionary key types/order, typed arrays, numeric
types, and exact floating-point bits; JSON is only the report format.

Coverage includes:

- A 7,800-case valid scalar grid for both actors; integer/float pools and
  options; finite extremes through the largest double; subnormal values
- 6,000 deterministic samples assembled from arbitrary finite float bits
- 1,215 exhaustive selected zero-sign/type combinations, plus explicit
  `-0.0` component versus `+0.0` accumulated-total checks
- 2,720 one-ULP shield/life boundaries and full depletion/overkill
- 17,745 pairwise invalid-input/error-priority combinations across raw amount,
  fire resistance, resources, mana, ratio, and bonus, with valid/unknown actors
- The complete raw → actor → resistance → shield → health → ratio → mana →
  bonus error precedence chain; disabled mana remains ignored
- 18,000 player/mana/bonus fallback combinations and omitted argument arities
- Public resolved/mana settlement with malformed packets, inconsistent totals,
  invalid details and resources, and post-hit multiplier paths
- Ordinary hit/source-hit adapters, component and profile APIs, metadata,
  and independent nested return ownership

The constructor retains `0.0; total += amount`, the original `minf`/`maxf`
argument and arithmetic order, a typed `Array[Dictionary]`, fresh nested
containers, and `StringName` keys for the original property-assigned actor and
stage. It introduces no cached DPS, alternate damage formula, state or RNG.

## Preserved failed iterations

`run-01.log.txt` records the first local exact-byte failure: the constructor
used String keys for actor/stage, whereas the original property assignments
produce StringName keys. The only production correction was changing those
two key literals to StringName.

`run-02.log.txt` records all 58,546 oracle comparisons passing, but one
independent test expectation still listing those two keys as String. Only the
test expectation was corrected afterward. Run 3 is the first passing batch.
These were local equivalence fixes to the same candidate, not new variants.

## Call-level timing only

The passing batch then measured seven alternating pairs of 6,000 ordinary
monster burn calls, after 1,000 warm-up calls per implementation. Both consumed
the same exact receipt totals. Median time was 82,997 → 43,028 microseconds,
a 48.16% reduction for this isolated call workload. Raw samples are retained
in `results.json`. This does not establish scene/frame-time improvement.

Unwrapped full-scene equivalence and timing, save bytes, events/rewards/RNG,
normal control behavior, and any release decision belong to the parent's
separate same-state scene batch. No project import, UI, export, schema/version,
or full historical-suite run was performed by this rules batch.

## Independent oracle and reproducibility

`source/` retains exact Git source bytes as `.gd.txt`. `frozen/` contains only
the complete two-script preload closure: defense rules and DamageResolver.
Its sole transformations remove global class declarations and relocate the
preload to the frozen dependency. It never preloads production code.
`manifest.json` records original and transformed SHA-256 values.

The freezer verifies both original and transformed bytes against the pinned
Git object, rather than trusting a hash regenerated from local production.
From the project root:

```sh
python3 docs/qa/v063-settlement-rules/freeze_oracle.py --verify
XDG_DATA_HOME=/tmp/godot-m1-v063-settlement-rules-data \
XDG_CONFIG_HOME=/tmp/godot-m1-v063-settlement-rules-config \
XDG_CACHE_HOME=/tmp/godot-m1-v063-settlement-rules-cache \
/usr/local/bin/godot --headless --path . \
  --script res://tests/burn_settlement_equivalence_test.gd
```

Check both the process exit code and output for `SCRIPT ERROR:` / `ERROR:`.
The focused script verifies the frozen/source hashes before running.
`scope.json` pins the tested production/test files and confirms all existing
functions except `incoming_burn` remain byte-for-byte original. The private
constructor is the only new function.

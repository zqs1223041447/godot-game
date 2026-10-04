# v0.40 pure attack-hit leech rules

This is the game's explicit dual-resource prototype, not an implementation claim for the complete Path of Exile leech system. The pure layer owns arithmetic and validation. Its caller owns player-only admission, actual-hit admission, per-run recovery pools, current aggregate caps, and resource-full cleanup.

## Public interface

- `STAT_KEYS`: exactly the eight supported fraction/increase fields: `attack_life_leech`, `attack_mana_leech`, `physical_attack_life_leech`, `physical_attack_mana_leech`, `life_leech_rate_increased`, `mana_leech_rate_increased`, `life_leech_max_rate_increased`, `mana_leech_max_rate_increased`.
- `profile(stats)`: current `{ok, reason, health, mana}` wrapper. A valid resource contains exactly `attack_fraction`, `physical_attack_fraction`, `instance_amount_cap`, `instance_rate`, and `total_rate_cap`.
- `from_stats(stats)`: omits the optional raw snapshot when all amount fractions are zero/missing and present leech inputs are valid. Valid rate-only inputs do not opt in. An active or malformed source yields detached raw maxima plus all eight fields, with missing modifier values defaulted to `0.0`; malformed values retain their type for later rejection. Missing maxima are acceptable only in an otherwise inactive legacy source. Unrelated derived-stat fields are not copied.
- `error(snapshot)`: validates optional `leech_modifiers`; present raw modifiers must be a nonempty dictionary containing only the eight stat names and `max_health` / `max_mana`. Both maxima are required and positive. Extra surrounding snapshot fields are outside this schema.
- `compile(snapshot, primary_tags)`: returns `{ok, error, leech}`. It validates malformed raw values before checking event scope. With positive amount fractions and the event's own `attack` plus `hit` tags, the emitted leech is exactly `{health, mana}`; otherwise it is empty. Spells, utility skills, and the authored independently tagged secondary explosions do not qualify.
- `profile_error(leech)`: validates exactly the compiled `{health, mana}` payload and five exact fields per resource. The current-profile wrapper is deliberately not accepted here.
- `plan_hit(leech, packet, settlement)`: returns `{ok, reason, health, mana}` with exactly `{amount, rate}` per resource. On any failure both resource outputs are zero. No input is mutated and no random stream is read.

## Arithmetic

For each resource with current maximum `M`, the current profile is:

```
instance_amount_cap = 0.10 * M
instance_rate       = 0.02 * M * (1 + matching_rate_increased)
total_rate_cap      = 0.20 * M * (1 + matching_max_rate_increased)
```

There is no base amount of leech. Life and mana have independent amount fractions, maxima, rate increases, and total-cap increases. Rate changes do not change the per-instance amount cap. All accepted scalars are finite numbers, never booleans; fraction/increase values are nonnegative without artificial gameplay maxima. Derived rates/capacities and compiled rates/capacities must be strictly positive; overflow and zero-producing underflow reject.

Hit planning consumes already resolved damage; it neither reads the packet's base damage nor applies armour/resistance/critical multiplication again:

```
D = shield_spent + health_lost
physical_applied = D * (components.physical / damage_total)
amount = min(instance_amount_cap,
             D * attack_fraction + physical_applied * physical_attack_fraction)
rate = instance_rate
```

With zero damage, physical applied damage is zero without division. A non-attack or non-hit event gets zero amounts. The frozen `total_rate_cap` is available for display but does not alter hit planning; runtime uses the current cap independently. Products and the uncapped amount sum are checked for overflow before applying the instance cap.

Resolved components accept only physical, fire, cold, lightning, and chaos. `damage_total`, `shield_spent`, `health_lost`, and `overkill` must be present and finite/nonnegative. Component sum must agree with total; actual damage must not exceed total; actual damage plus overkill must agree with total. A relative tolerance of `1e-12` admits floating arithmetic roundoff, with no absolute epsilon that would turn tiny nonzero damage into zero. Overkill is validation/accounting data and never contributes to a leech amount. A present settlement `ok` must be boolean true. Existing extra Defense settlement fields are accepted and preserved.

## Independent numeric examples

For maxima health=1000 and mana=400, generic fractions .05/.04, physical fractions .10/.06, rate increases .5/1, and cap increases .25/.75:

- Life instance capacity=100, rate=30, aggregate cap=250
- Mana instance capacity=40, rate=16, aggregate cap=140
- Resolved 60 physical + 40 fire, shield spent 20, life lost 30, overkill 50: actual damage=50, actual physical=30; life amount=5.5, mana amount=3.8
- The same hit wholly absorbed by 100 shield gives life=11 and mana=7.6, identical to 100 actual life loss
- Only 1 shield + 1 life with 98 overkill gives life=.22 and mana=.152
- Existing Defense armour example: 100 physical + 50 fire against 500 armour becomes 50 physical + 50 fire; with 20 shield + 60 actual life loss, life amount=8 and mana amount=5.6

## Focused validation

Command (isolated XDG paths, existing shared worktree, no full project import):

```sh
XDG_DATA_HOME=/tmp/v040-leech-rules/data \
XDG_CONFIG_HOME=/tmp/v040-leech-rules/config \
XDG_CACHE_HOME=/tmp/v040-leech-rules/cache \
/usr/local/bin/godot --headless \
  --path /workspace/scratch/a51485f153de/v040-dual-resource-leech \
  --script res://tests/leech_rules_test.gd
```

Godot `4.6.3.stable.official.7d41c59c4`: **1,213 checks, zero failures**. See `leech-rules-test.log.txt` and `leech-rules-tested-files.json` for the run and content hashes.

Coverage includes direct mixed/elemental/physical math, shield and life equivalence, overkill exclusion, real armour-resolved Defense settlement, independent capacities/rates, display-cap independence, missing legacy snapshots, valid rate-only omission, malformed-value preservation, strict raw/profile keys, spell/secondary exclusion, wrong types/booleans/NaN/infinities/negative values, missing and inconsistent settlements, underflow/overflow, atomic zero failures, order independence, deep detachment, and unchanged RNG state.

This evidence covers only the pure rule layer. Runtime timing, compiler integration, source-tree coverage/migration, and UI/gameplay checks are tracked separately by their owners.

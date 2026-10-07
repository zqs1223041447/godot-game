# v097 diagnostic nonlethal batch guard

`tools/diagnostics/burn_batch_guard.gd` is a pure, unregistered preflight helper.
It does not call Main, apply damage, advance statuses, draw RNG, reserve feedback,
or mutate inputs. It neither selects burn replacements nor introduces balance
changes. There are no production changes in this guard work.

## Caller contract

Call `plan(events, enemies, statuses, start, end, original_delta)` before **any**
Main settlement side effect, with the original complete event array, complete
current monster array, and full detached `BurnRuntime.statuses()` array. The
caller also requires empty ShockRuntime and no outstanding deferred deaths or
other pre-existing settlement work. The guard cannot inspect omitted actors,
omitted statuses, ShockRuntime, or Main's pending work through this API.

If `ok` or `eligible` is false, execute the whole original Main batch unchanged.
There is no mid-batch fallback and no rollback of already executed work. The
wrapper can bypass empty batches rather than paying for this diagnostic plan.

Success returns:

- `ok=true`, `eligible=true`, `reason=""`
- `budget_end=end`: the endpoint used only for conservative damage budgets
- `last_boundary`: maximum of the initial monster burn clock and normalized
  **hit** boundaries; this is a planned watermark, not an instruction to advance
- `burn_ids`: sorted initial and possible new burn target IDs
- `bounds`: integer target ID to `health`, `direct_upper`, `max_raw_dps`,
  `burn_from`, `burn_upper`, and `total_upper`

Failure returns `ok=false`, `eligible=false`, a reason, no bounds or IDs, and
`last_boundary=start` (or zero for invalid start). No partial proof escapes.
Returned arrays/dictionaries share no mutable objects with inputs. The wrapper
must track its actual original burn-advance calls, and must not advance survivors
to `budget_end` before the original spawn-flush boundary.

## First admitted domain

- One to 100 unique current monsters, all living with finite positive health,
  zero shield, finite known resistances, and nonnegative armour/spawn/evasion data
- One to 100 valid current monster burns, with at least one active ember lineage;
  no player, missing, duplicate, expired, or inconsistent detached status
- Finite positive actual original delta, at most exactly `1.0 / 60.0`; adding it
  to start must reproduce end and move the clock forward
- Every existing expiry and every possible new burn expiry is strictly after end
- Raw event order normalized through the existing `prepare_events` helper, which
  delegates to `EmberEventClock.offsets`; approximate adjacent raw ties retain
  their original order, while true reversals and out-of-window offsets reject
- Direct `hit`, or benign `terrain_hit`, `terminated`, `return_started`, `split`,
  and `evaded` events; explosions reject because secondary RNG is not frozen
- Known ordinary Combat/Compiler snapshot fields, optional frozen critical result,
  and supported burn policy/multiplier/faster fields; absence of critical_roll
  uses multiplier one, exactly as Main does

`critical_modifiers` is admitted as existing compiler metadata only after the
original `CriticalStrikeRules.error` validation. Existing compiled profiles pass
`CriticalStrikeRuntime.snapshot_error`. Direct Main settlement uses only
`critical_roll`, never recomputes those modifiers, and explosions that could
freeze a new roll remain excluded. This was checked with
the exact v095 damage-0.1, zero-critical-chance, tornado/ember compiler fixture.

Unknown event kinds and snapshot gates reject. This excludes leech, shock,
freeze, resolute/precise, source special modifiers/policies, and future effects
unless explicitly audited. The whitelist is intentionally restrictive. Payload
conversion/penetration is allowed only when the original Damage authority can
resolve it; unsupported conversion errors reject. Zero fire or absent burn
policy does not create an invented application.

## Bound rationale and limits

Each hit calls `Damage.resolve(payload, snapshot.modifiers, {}, frozen_multiplier)`.
The direct budget is twice the sum of its authoritative before-defense details.
This safely disregards resistance reductions and armour: current hit resistance
and penetration clamp at a lower bound of -1, so their maximum multiplier is two.
Shock is excluded by the caller and by snapshot admission.

For a burn-capable fire hit, the exact authoritative fire detail feeds
`BurnRules.from_fire_hit`, including the existing fire DoT/faster fields. The
guard does not reconstruct modifiers, conversion, critical, or burn formulas.
For each target it takes the maximum existing/new raw DPS and charges that DPS
over the entire end minus old-last interval, or end minus start for a new target.
It then uses a deliberately loose factor of two for the burn defense ceiling
(current monster burning actually clamps fire resistance nonnegative). This
overcounts late applications and refreshes. Equal/stronger/weaker burn selection
and application are still performed only by original Main/BurnRuntime.

All hit ceilings accumulate per target. Admission requires
`direct_upper + burn_upper < health * 0.5`. Half-health is a conservative
diagnostic eligibility margin, not a gameplay multiplier or tuning parameter.
It excludes every possible death/spread in this first domain, including damage
to targets not directly hit in the batch.

Budget arithmetic rounds positive products and sums outward by one representable
double, and rejects nonfinite results, subnormal amounts, positive terms absorbed
by a sum, event offsets absorbed by the absolute clock, and total budgets smaller
than a target health ULP. This is a conservative supported-domain argument and a
large numerical margin, **not a formal proof covering every floating-point
settlement order**. It does not claim binary-identical health, feedback totals,
or complete lazy-settlement equivalence; the Main diagnostic comparison owns
those observations and must report differences honestly.

## Focused validation

Run without editor import, long simulation, or performance measurement:

```sh
XDG_DATA_HOME=/tmp/godot-m1-v097-guard-data \
XDG_CONFIG_HOME=/tmp/godot-m1-v097-guard-config \
XDG_CACHE_HOME=/tmp/godot-m1-v097-guard-cache \
godot --headless --path . --script tests/burn_batch_guard_test.gd
```

The fixture refuses another XDG data prefix. `results.json` and `run.log` record
the 78-check full run before the later one-key metadata whitelist correction.
`critical-metadata-after.log` records the final eleven-check focused rerun of
that correction and the original critical-validator gates; there was no
additional full-suite run. `validation-history.md` and
the receipts distinguish exact source versions and overlapping check counts.
Cases cover nonlethal/near-half/lethal budgets, all-target
shields, expiry equality, unsupported effects, unknown events/types, accumulated
hits, stronger/new burns, frozen criticals, authoritative conversion/penetration,
raw ties/reversals, invalid delta, bad/overflow/sub-ULP inputs, real compiler
snapshot admission, and unchanged input bytes through success and fallback.

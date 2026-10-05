# v0.52 pure shock rules and runtime

These are this game's frozen prototype policies:

- Player: `duration: 2.0`, `hit_damage_taken_increased: 0.15`,
  `hit_multiplier: 0.80`, `mana_multiplier: 1.20`.
- Enemy: `duration: 1.0`, `hit_damage_taken_increased: 0.15`.
- `ShockRules.policy_error(policy)` accepts only those two complete policies.
  Unknown fields, alternate strengths/durations, missing fields, booleans, and
  nonfinite/nonpositive numeric fields are rejected. Numerically equal integer
  values such as enemy duration `1` are accepted.
- `from_lightning_hit(actual_lightning, policy)` requires a finite positive
  actual lightning component after hit settlement. It returns
  `{ok, reason, duration, hit_damage_taken_increased}`; failure zeros both
  numeric fields. Positive damage magnitude does not scale shock. The helper
  does not repeat the upstream hit or mana multiplier.

## Caller-owned damage ordering

The caller obtains `status_at(kind, id, original_hit_time)` before resolving a
hit, applies its increased damage taken modifier to that hit, and only then
attaches or refreshes shock if settled actual lightning damage is positive.
This ordering prevents the triggering hit from benefiting from the shock it
creates. An already shocked target can benefit the next ordered hit even at
the same exact timestamp. Damage over time must not query or consume this hit
modifier. The pure runtime neither resolves damage nor distinguishes damage
channels, so actual settlement and DOT exclusion require integration coverage.

The query uses the original authoritative hit timestamp. It must not receive a
later timestamp normalized for the burn scheduler. The runtime uses exact
comparisons, never accumulated elapsed time as a fuzzy tolerance. Outer gameplay
code validates the complete near-tie event batch before settling any hit: raw
offsets and tie ordering must be legal, the maximum reversal span must be less
than the shortest policy duration (one second), and the earliest absolute event
time must be at or above `read_floor()`. The fixed gameplay step is shorter than
one second, so one target cannot fully expire twice within one legal batch.

`ShockRules.projectile_batch_error(events, step_start, step_end, read_floor,
original_delta = null)`
provides this whole-batch preflight as an empty String on success or an error
reason on failure. Window times must be finite nonnegative int/float values,
with end at or after start. It reuses `EmberEventClock.offsets` unchanged to
validate the existing adjacent raw-offset tie chains. Every raw offset must be
inside `[0, original_delta]` when the finite nonnegative original simulation
delta is supplied. The compatible four-argument call instead uses
`[0, step_end - step_start]`. Gameplay supplies its actual simulation delta:
subtracting accumulated timestamps can round this reconstructed width below a
legal raw endpoint. No approximate elapsed-time tolerance is introduced.
Each finite absolute time is still computed as `step_start + raw`, clamped to the
window and must be at or above the read floor. Every normalized offset minus
its raw offset must be strictly less than one second. A sequential large-delta
batch remains valid; only the reversal span is bounded. Inputs and their nested
payloads are not modified. Failure in a late event rejects the complete batch,
so the caller must invoke this helper before dispatching even the first hit.

## Runtime API

- `apply(kind, id, source_id, at, policy, provenance = {})` returns
  `{ok, reason, applied, refreshed}`. A new or expired target yields `new`,
  `applied: true`, `refreshed: false`. Same-time or later applications while
  active yield `refreshed`, `applied: true`, `refreshed: true`; strength never
  stacks. A fully valid application earlier than the currently stored
  `refreshed_at` returns `ok: true`, `reason: older_application`, and both flags
  false, without changing source, provenance, application/refresh time, or expiry.
  A continuous active refresh retains the interval's original `applied_at`
  and updates `refreshed_at`; a new application at or after expiry resets both.
  Expired replacement retains the previous continuous interval for queries in
  the current event window. A second replacement evicts the oldest interval and
  advances the global read floor to at least that discarded interval's expiry.
- `status_at(kind, id, at)` returns
  `{ok, reason, active, hit_damage_taken_increased, status}`. The active interval
  is exactly `applied_at <= at < expires_at`. Missing, future, or expired status
  is valid but inactive, with zero modifier and an empty status dictionary.
  Invalid reads return the same inert shape with `ok: false`. Queries never
  advance time, mutate a status, or prune it. Reads check the current interval
  first, then the single retained previous interval. Each read remains O(1).
- Active detached `status` dictionaries contain `target_kind`, `target_id`,
  `source_id`, `applied_at`, `refreshed_at`, `expires_at`, `remaining_seconds`,
  `hit_damage_taken_increased`, and `provenance`. The arena wrapper resolves
  actor position for rendering; this pure store holds no actor references.
- `statuses(at)` returns detached active dictionaries in lexical kind order
  (`monster`, then `player`), then numeric target ID. Invalid timestamps yield
  an empty array, as do timestamps below the read floor. At most one matching
  interval is returned per target. This bounded presentation read is not a
  per-hit lookup.
- `prune(at)` returns `{ok, reason, removed}` with an integer removal count.
  It removes current and previous intervals with `expires_at <= at` and advances
  the read floor to that frame end; the count is removed current target slots,
  not discarded prior intervals. Invalid or below-floor time changes nothing.
  Gameplay calls it once per frame after that frame's events. Neither `apply`
  nor `status_at` performs a hidden full-state scan.
- `remove(kind, id)` returns `{ok, reason, removed}` with a boolean removal flag.
  It clears that target's current and previous intervals without moving the
  global read floor. Removing one actor's incoming shock does not remove that
  actor's outgoing shock on another target.
- `read_floor()` returns the inclusive oldest valid event timestamp. It starts
  at zero, only increases on successful pruning or history eviction, and causes
  `apply`, `status_at`, and `prune` at older timestamps to fail explicitly before
  mutation. Exact-floor timestamps remain legal.
- `reset()` clears every current/prior state, cached identity, and the read
  floor; `is_empty()` reports retained target slots, including expired entries
  awaiting explicit frame cleanup.

This is ephemeral storage for the current continuous interval plus at most one
previous interval per target. If shock existed at time 0, then a refresh at
1.000002 does not prevent the slightly earlier hit at 1.000001 from seeing that
old shock. If 1.000002 was instead the first application, the earlier hit is
inactive. Application after an expired gap starts a new interval and does not
fill that gap. If `[0, 2)` is replaced at `2 + 1 ULP`, an original event at
`2 - 1 ULP` can still read the retained old interval, including its old source
and provenance. Continuous refreshes do not retain every historical source
within one interval, whose frozen strength is unchanged. Discarded history is
explicitly closed by the read floor, not silently reported as absent shock.
Removal/reset still discard the target's states; gameplay owns actor liveness.

## Validation and bounds

- Kinds are exact Strings `monster` or `player`. Monster IDs are positive exact
  integers; player ID is integer zero. Source IDs are nonnegative exact integers.
  Float IDs, booleans, StringNames, and coercible strings are rejected.
- Times are finite nonnegative integers/floats, including zero. Expiry addition
  must be finite and strictly later than the application time; timestamps too
  large to represent the positive duration are rejected before mutation.
- At most 101 identities are retained, each with at most one previous interval
  in addition to its current interval. Existing targets can refresh at capacity;
  an additional identity fails atomically. Expired entries retain their slots
  until explicit pruning, so there is no per-hit full scan.
- Provenance allows only exact String keys `skill_id`, `cast_id`,
  `projectile_id`, and `phase`. Text is an exact String of at most 128 characters
  and may be empty. IDs are nonnegative exact integers and may be zero. Unknown
  fields, nested containers, and wrong types are rejected.
- Every validation finishes before any state mutation, including for an older
  application that would otherwise be ignored. Caller policy and provenance
  inputs are never modified. Getter lists, status dictionaries, provenance,
  and empty query results do not expose mutable internal state.
- No RNG, save/load, signals, scene access, defense, leech, damage integration,
  or propagation is part of either production file.

## Verification

`tests/shock_rules_runtime_test.gd` covers the above pure policy and runtime
contracts, including exact-time ordering, near-ties at large elapsed times,
expiry equality, refresh attribution, future-read isolation, invalid-input
atomicity, source death versus target cleanup, detached copies, deterministic
ordering, bounded storage, and global RNG preservation. It also covers before/
at/after-expiry ULP interleaving, continuous refreshes, inactive gaps, second
history eviction, explicit historical errors, exact read-floor legality, and
large sequential time jumps without fuzzy tolerance.

The focused command uses the repository's temporary XDG isolation:

```sh
bash tools/validate.sh res://tests/shock_rules_runtime_test.gd
```

On Godot 4.6.3 the final selected command passed with **910 checks, 0 failures**.
The successful log is `pure-run-03.log`; `pure-tested-files-03.json` records the exact
command and SHA-256 of six inputs before and after execution, all unchanged.

The first run is retained as `pure-run-01.log` and
`pure-tested-files-01.json`: 877 checks, 9 failures, including an interrupted
ULP case. It exposed an actual policy-validation issue: Godot Dictionary equality
distinguishes int and float values, so a numerically exact integer duration was
rejected. Frozen-policy comparison now validates types first and compares each
numeric value exactly after float conversion. Separately, decimal ULP test
literals rounded onto the expiry boundary during parsing; the fixtures now use
double bit-pattern neighbors. The second run completes those cases and passes
with 890 checks, preserved in its separate `02` log and source-hash record.
The third run adds the approved original-delta endpoint correction and its
20 checks: legal endpoints at start times 1, one million, and one billion;
four-argument compatibility; strict raw bounds; retained-floor checks; malformed
optional deltas; and preserved input events. Final production rules/runtime and
the focused test were not edited after the successful third run; only this
verification narrative was updated afterward.

Pure coverage does not claim gameplay damage-channel integration, main's batch
dispatch wiring, UI, save migration, native rendering, or release/export
validation.

# v097 pure burn-deadline shadow queue

Baseline: `d2d188ab3aa284a1abbb7d9e382eaf976678aab2`.

`tools/diagnostics/burn_deadline_shadow.gd` is an unregistered `RefCounted`
diagnostic with no production caller. It owns scalar snapshots and predicted
deadlines only. It never mutates actors, damage resources, BurnRuntime, expiry
state, transfer selection, RNG, scenes or saves. No new scheduler equivalence
or performance improvement is claimed. Floating-point prediction uncertainty
is not solved by this queue.

## Contract

Each input row has exactly these String keys:

- `target_id`: positive integer monster identity
- `last_time`: finite integer/float, at least zero
- `raw_dps`: finite integer/float, greater than zero
- `expires_at`: finite integer/float, strictly after `last_time`
- `shield`: finite integer/float, at least zero
- `health`: finite integer/float, greater than zero
- `fire_resistance`: finite integer/float; existing Defense owns the cap
- Optional `revision`: nonnegative integer caller metadata

Strings, booleans, containers and other scalar-like values are not coerced.
Unknown keys and StringName keys are rejected. In GDScript, introduce the
optional key with `row["revision"] = n`; adding it with property syntax can
create a StringName key. Accepted row scalar types and signs are preserved.

- `configure(rows: Variant) -> Dictionary`: validate a complete Array first,
  reject duplicate identities, then atomically replace the entire queue
- `upsert(row: Variant) -> Dictionary`: atomically insert or replace one row;
  success includes `replaced` and a detached `entry`
- `remove(id: Variant) -> Dictionary`: success includes `removed`; a valid
  absent ID is a successful no-op
- `peek() -> Dictionary`: detached minimum entry, or a fresh empty dictionary
- `pop_due(to_time: Variant) -> Dictionary`: `{ok, reason, entries}`; validates
  a finite nonnegative cutoff, removes every deadline at or before it and
  returns detached entries in exact deadline/ID order
- `entries() -> Array`: detached sorted entries
- `snapshot() -> Dictionary`: detached heap, ID-to-index map and generation
- `is_current(ticket: Variant) -> bool`: whether the ticket's queue identity,
  target ID and internal generation still designate a current node
- `clear()`: discard every node and index; retain the generation counter

`pop_due` is a cutoff operation, not a gameplay clock advance. It does not
forbid a later query with a smaller cutoff or submit backdated rows on behalf
of its caller. Callers own chronology, settlement and refresh policy. For
example, after a weaker application they submit the accepted old DPS and
expiry with the updated resources/clock; the queue never decides which burn
application wins.

The indexed minheap and ID map each hold at most 100 entries, with one live
node per identity and no stale tombstones. Configure heapifies in O(n);
upsert/remove take O(log n); peek takes O(1). Exact unequal deadlines never
tie, including adjacent doubles. Exact ties use ascending target ID.

Each accepted insert/replacement receives a fresh generation from one int64
counter. Removed IDs have no retained metadata. Clear/configure/pop/removal
cannot make old tickets current again after identity reuse. The counter never
resets or wraps; exhaustion explicitly rejects future insertions/replacements.
Caller `revision` is independent metadata, so equal or lower caller revisions
do not revive old tickets. Tickets are version checks, not security tokens.

## Prediction and fallback boundary

Rate comes only from the existing call
`Defense.incoming_burn(raw_dps, fire_resistance, 0.0, 1.0, "monster")`.
The original arithmetic is retained:

`death_at = last_time + (shield + health) / damage_total`

If this rounds to `last_time` or below, the original Main double-bit increment
is applied. Nonfinite or non-forward results then reject atomically. In the
degenerate negative-zero/underflow case, that original bit increment produces
a negative subnormal; this shadow rejects it rather than repairing production
arithmetic. Ordinary negative-zero timestamps remain valid when death is
strictly positive.

`deadline = min(death_at, expires_at)`. Kind is `death` when
`death_at <= expires_at`, including an exact death/expiry tie. Thus the caller
must settle that death ticket before removing the associated expiry. The
queue does not enqueue a second expiry record or impose a cross-target
death-before-expiry tie rule; exact cross-target ties still use target ID.

Every rejection returns `ok: false` and a nonempty stable reason with no heap,
position or generation change. Derived-arithmetic failures use explicit
`fallback_required_*` reasons: unrepresentable expiry (e.g. adjacent large
integer timestamps collapse to the same double), defense rejection, zero or
unrepresentable rate, shield-plus-health overflow, unrepresentable death time,
or exhausted generation. Even if expiry would happen earlier, an overflowing
death prediction is rejected, not silently replaced with an expiry ticket.

## Oracle and evidence

`old_complete_prediction.gd` adapts the entire original per-status prediction
scan, rather than reading expected values from the queue. The original source
block is in `original-main-prediction.txt`. The runner checks its bytes against
pinned Main and mechanically verifies the adapter: one indentation level is
removed; supplied statuses replace the runtime read; removal of missing/dead
actors becomes a pure `continue`; and an extra dictionary records the already
computed prediction. The expression, comparison order and ULP code stay exact.
The entire literal Defense preload/load dependency closure and `project.godot`
are SHA-256 pinned by `oracle_manifest.json` and checked before/after each run.

One full pure batch ran, followed only by affected-group verification:

- `run-vgrpioi8/`: first run, 22,699 checks, 500 oracle cases, exit 1.
  Five failed assertions and one resulting empty-dictionary access came from
  fixtures: optional revision was introduced as a StringName, and literal
  negative zero did not preserve the intended distinct bits in the constant
  pool. The entire original log, exit, hashes and source bytes are retained
- `run-0b3kez49/`: only refresh, validation, extremes and oracle groups rerun
  after explicit String-key and bit-pattern fixture fixes; 3,028 checks,
  500 oracle cases, zero failures, exit 0, 1.830 seconds. Source queue bytes
  were identical in both runs. Capacity/update, removal/tickets, exact ordering,
  detached aliases and deterministic mixed-operation groups were unchanged
  and had passed in the initial run

The runner rejects `ERROR:`, `SCRIPT ERROR:`, parse errors, missing summaries,
nonzero exit, input changes and failed checks; a superficially successful exit
cannot hide a failed script. Each run keeps independent XDG data/config/cache
under `/tmp/godot-m1-v097-queue-*`, a 35-second guard and the existing copied
`.godot` cache. No editor, import, gameplay battle or benchmark was run.

The test covers 100-capacity/101-reject, 1,200 replacements without heap/index
growth, root/middle removal, reuse/clear/configure/pop invalidation, exact and
adjacent-double deadlines, cutoff boundaries, death/expiry classification,
caller-modeled weaker/equal/stronger refreshes, malformed schemas and scalar
types, signed zero/nonfinite/overflow cases, atomic errors, detached aliases,
500 old-scan oracle cases and 360 deterministic mixed operations with a
separate simple model. Read existing evidence first; additional Godot runs
are unnecessary unless an affected implementation/test changes.

To run deliberately, use `python docs/qa/v097-queue/run_checks.py`.
Affected-only selection uses one comma-separated `--only=` argument naming
test functions, as recorded verbatim in the second evidence file. The runner
never overwrites prior run directories.

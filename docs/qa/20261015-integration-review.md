# Integrated transaction-fix review — 2026-10-15

Decision: no blocking finding in the reviewed four-file production diff against 000ef21. Read-only production review; no repository edits, staging, commits, or import/editor jobs were performed by this reviewer.

## Reviewed semantics

- `scripts/main.gd:3094–3110`: return flushes pending progress while the map still has its active completion identity. Failed flush or failed abandonment leaves a live run that can still settle. Successful completion already contains its canonical reward receipt. No later save remains between committed abandonment and the local town transition. Reviewed `_flush_progress`, `_attempt_progress_save`, change receipts, restart, and normal completion flow; persisted commits are recognized by exact snapshot receipt, preventing an unnecessary busy reentrant autosave.
- `scripts/canonical_game_state.gd:181–202,557–578`: move-and-bind uses the same paged validated transfer planner as `move_item`, then one canonical commit. It retains busy rejection, UID ownership, destination legality, displacement validation, and persistence-before-signal behavior. Missing-key same-location repair is allowed; a complete legacy no-op still returns false. Identical explicit bindings are order-preserving no-ops. Canonical validation remains the final gate.
- `scripts/main.gd:1770–1786`: F6 stops at each failed constituent transaction, reports partial completion truthfully, skips already fulfilled steps on retry, and handles already complete builds as success without writes.
- `scripts/ui/canonical_inventory_panel.gd:320–338,386–391` and `scripts/ui/canonical_skill_panel.gd:178–185`: success/no-op replace old error feedback. Discard invalidation clears its request before dialog/feedback callbacks. Ordinary skill actions remain individually transactional; the compatibility helper is not substituted into canonical skill UI.

## Independent executed checks

Godot 4.6.3, headless, isolated new `/tmp` XDG data/config/cache for each process, timeout 90 seconds each. All five processes exited 0; 183 checks total, no failed assertions or script errors:

1. `skill_transaction_atomicity_test.gd`: 108 checks, zero failures. Atomic failure/success, same-location repair, existing/default/rebound keys, repeats, exact disk/memory/reload, one revision/write/signal, idempotence throughout binding array, stale/invalid binding.
2. `canonical_ui_feedback_recovery_test.gd`: 19 checks, zero failures. Actual main HUD/panel handlers, write-failure recovery, no-op feedback, discard revision invalidation, synchronous late confirmation, stale retained request, cancel/hide, failed and fresh discard.
3. `tornado_example_failure_test.gd`, TORNADO_UNBOUND=1, TORNADO_FAIL=3: 17 checks, zero failures. Reachable F6 partial result at third write, complete retry, disk equality and repeated no-op.
4. `return_transaction_failure_test.gd`, RETURN_CASE=second_clear, RETURN_FIXTURE=affixed: 26 checks, zero failures. Paid affixed run, failed second return write, retained active identity, continued full clear, exact receipt, return, scene reload, safe-exit idempotence.
5. Independent `/tmp/integration_extra.gd`: 13 checks, zero failures. Fill a bag through real gem admission, persist, swap group-to-group with full bag, swap bag-to-group using the vacated gem cell, preserve every UID/payload, reject `slot_skill` reentry during changed emission, single signal, disk reload equality, invalid indices/skill leave snapshot unchanged.

Logs: `/tmp/integration-review-logs/{skill_transaction_atomicity,canonical_ui_feedback_recovery,tornado_example_failure,return_transaction_failure}.log`; `/tmp/integration-extra.log`. `git diff --check` clean.

## Limits

This is code/transaction and headless behavioral review, not mouse/pixel/manual playtesting or an exhaustive all-map/all-affix/all-support matrix. The F6 sequence deliberately permits persisted partial application with explicit feedback. All return fault positions and broader F6 matrix execution are owned by the implementation workers; this reviewer independently reran the representative cases listed above. Full-bag rejection from recovery was not dynamically recreated; the unchanged transfer planner still handles it before candidate binding/commit. Generated preexisting import/UID artifacts were neither cleaned nor staged.

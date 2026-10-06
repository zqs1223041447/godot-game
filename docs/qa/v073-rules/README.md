# v0.73 frost-lock pure rules and runtime

Result: **501 checks passed, 0 failures**, first focused run, **0.61 seconds**.
Exit 0; no script or engine errors; all captured inputs stayed unchanged.

- `20261006T074340774521Z-run.log.txt` is the unchanged engine output
- `20261006T074340774521Z-receipt.json` records the command, exit, duration, isolated user profile, and before/after SHA-256 inputs
- `run-focused.py` runs only `tests/frost_lock_rules_runtime_test.gd`, after the parent's shared Godot import, with a 30-second watchdog

## Verified contracts

- The only policy is the exact frozen player shape: normal/magic 0.60s, rare 0.35s, boss 0.20s; 1.50s immunity after thaw; hit multiplier 0.75 and mana multiplier 1.20. Missing, extra, non-String, nonfinite, or retuned fields fail closed; the compiled `enabled` marker is not accepted in the snapshot policy
- Only a frost projectile hit with positive finite actual cold shield/health loss and a living target qualifies. Secondary packets, damage over time, absent hit tags, other skills, malformed inputs, zero loss, and dead targets do not qualify
- Freeze and immunity use exact half-open intervals. Same-time and subsequent frozen/immune hits cannot refresh, stack, extend, or rewrite rarity/provenance. Exact immunity expiry permits a new interval
- One state per positive integer monster ID, at most 100. Retained immunity/expired states count toward capacity until explicit remove/prune; removal and exact-expiry pruning release capacity without hidden per-hit scans
- All input checks and capacity failures are atomic. Apply/prune reject reversed settlement time; malformed and unbounded provenance, nonfinite times, overflow, and rounded-away lifetimes/frame widths are rejected
- Policy/provenance inputs, state getters, and prefix maps are detached. Query order never mutates storage or timing. Missing and invalid query IDs are harmless empty reads
- Frame queries emit only positive blocked prefixes. They allow partial thaw and future intervals outside the span, while rejecting an unsupported freeze start inside the span without a partial result
- A large-delta model preserves the frozen prefix until after the enemy phase, pauses motion/cooldown/windup clocks for that prefix, and advances only the remaining unfrozen time. Pruning after that phase releases completed immunity
- Explicit removal/reset clears status promptly; reset also clears the old scene's settlement clock. Every operation preserves the global RNG sequence

This focused proof loads no Main scene, actor, save, damage settlement, or live AI scheduler. Actual cold attribution, birth protection, deaths/resets, presentation, and production enemy-clock integration are covered separately by the gameplay/presentation owners. No export, package, or historical test collection was run here.

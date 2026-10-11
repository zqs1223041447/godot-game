# Zero/nonfinite-armour private-result copy elision

## Result and scope

Retained one minimal call-site change in `scripts/main.gd:1669–1672` against HEAD `ae39fff07a92e83d8df92829250ccb56d7ddf73e`. Converts enemy armour to float once, calls `Defense.apply_armour` only for positive finite armour. All other source is unchanged; in particular `scripts/mechanics/defense_rules.gd` matches HEAD byte-for-byte. Its public defensive-copy contract remains intact. Positive finite armour still takes the original adapter, including elemental-only total recomputation. No RNG, settlement, trace, arithmetic or other candidate changed.

Godot 4.6.3 stable, headless, dot workspace. No full suite, network, CLI authentication, cloud Codex, commit, push or export performed. Parent retained this report, summary.json, tick.json, oracle-production.log and shock-boundaries.log in the repository; other listed experiment files remain temporary.

## Ownership audit

`Damage.resolve` returns a fresh result dictionary, component dictionary and detail array in normal, converted, and failure branches. Normal details own fresh modifier-name arrays. Converted details own fresh parts arrays; parts own copied lineage arrays and new modifier-name/index arrays. No packet/snapshot dictionary or array is borrowed. The local result has not been shared before this adapter call. Therefore skipping a no-op defensive copy here does not weaken the public adapter's callers. Public adapter still deep-copies before its existing early return. Comparison uses `armour > 0.0 and is_finite(armour)`, the logical complement of its original early-return condition over floating-point values, including NaN.

## Strict equality verification

Same-source temporary main copies tested before production edit: 360 scenarios / 2,400 checks, including explicit new/refreshed shock assertions. Final production oracle expanded to 400 scenarios / 3,460 checks and passed. Production main bytes equal timed candidate bytes (SHA256 in summary.json).

10 armour cases: missing, +0.0, -0.0, negative, NaN, +infinity, -infinity, 1, 100, 1e300. Ten damage/snapshot cases crossed with four target/status cases: physical; elemental-only; mixed physical/fire conversion; mixed conversion plus cold/lightning penetration; empty base; invalid conversion; invalid penetration; invalid critical multiplier; valid shock attachment; v2 physical-to-cold/lightning conversion with penetration. Target cases: ordinary large health, shield, lethal health, pre-existing shock. Packet/snapshot inputs unchanged; later recursive input mutation cannot affect traces; later recursive trace mutation cannot affect enemy resources. Direct resolved bytes match old adapter output for every armour/damage combination. Mutating adapter output does not affect its input; mutating private resolved output does not affect packet/snapshot, including converted nested parts.

400 comparisons use exact `var_to_bytes` equality of inherited broad observer state, with observation outside timing. Covers main script non-object properties (enemy resources, traces, event counts etc.), RNG, canonical model snapshot, isolated save bytes, target-index and projectile/monster/feedback/cue/critical/burn/telegraph/cooldown/trap/chill/shock/freeze/leech/flask/geometry runtime non-object fields. Save bytes are compared but no build-write action is expected; noncanonical model internals are not observed. Inherited exclusions: `_flask_owner_identity`, `_previous_auto_accept_quit`, `particle_`-prefixed fields, all object/Callable/Signal properties. Does not prove equality of HUD/rendering or arbitrary object graphs/model caches.

Production shock settlement boundary test: 47 checks, zero failures. `git diff --check`: passed.

## Exactly one bounded clean paired tick run

One 24-tick old/new sequence; alternating execution order every tick. No warmup exclusion, retry, repeat benchmark or microbenchmark. Shared unchanged dependencies; only main call site differs. Fixture uses seeds 500050/500051, 100 real catalog actors, 180 artificial near-contact tornado carriers injected before each 1/60 tick, damage 0.075, no supports, player protected. Compilation, actor/carrier creation, observation, serialization and waits excluded from timing. Every paired tick has exact observed-state equality (24/24).

- Mean: 36.223 → 34.420 ms (−4.98%)
- Median: 35.613 → 34.169 ms
- Median paired difference: −1.401 ms
- Maximum: 46.376 → 37.980 ms
- Faster: 18/24 pairs
- Old-first half: 36.456 → 34.603 ms (−5.08%), 9/12 wins
- Candidate-first half: 35.991 → 34.236 ms (−4.88%), 9/12 wins
- First 12 ticks: −7.42%, 9/12 wins; last 12: −2.49%, 9/12 wins

Decision basis: the reduction recurs in both execution orders and both chronological halves, with 75% paired wins and a 1.4 ms median paired reduction. This is meaningful enough to retain the minimal copy elision within this bounded fixture. It is **within-run consistency**, not independent-run replication. Baseline slow ticks inflate the mean gain, variance remains, and the magnitude should not be promised. The prior instrumented 1.09 ms attribution was not used to predict savings. No whole-game FPS, GPU/render, Windows, formal-map or 300-actor claim. Timed fixture has no kills/rewards/burn; lethal and shock cases are covered separately by the untimed oracle.

## Evidence

- `main-old.gd`, `main-new.gd`, `build.py`: exact source copies and construction
- `probe.gd`, `tick.json`, `tick.log`: clean fixture and all paired observations/timings
- `oracle.gd`, `oracle-production.log`: final expanded production equivalence/ownership checks
- `oracle.log`: prior temporary-copy check (360 cases before adding v2 and trace-mutation coverage)
- `shock-boundaries.log`: production targeted regression pass
- `summary.json`: numeric aggregates and SHA256 source hashes

Only repository change: `scripts/main.gd`, four lines added / one removed. HEAD unchanged; no commit/push.

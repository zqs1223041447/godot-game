# v052 Shock actual-main integration

Verified on 2026-10-05 with `tests/shock_gameplay_test.gd`: **161 checks, 0 failures, process exit 0**, with no engine error, script error, or parse-error lines. Runtime: 2.73 seconds. This is the focused Shock suite, not a historical regression sweep or a 600-second density test.

The run used a fresh `/tmp/godot-m1-v052-shock-gameplay-18xp8u6l` XDG root. `gameplay-final.json` records the command, explicit process exit, all production GDScript and test SHA-256 values before/after, and the parsed completion summary. All source hashes remained unchanged during execution. `gameplay-final.log` contains the complete engine output.

| Actual-main coverage | Checks |
| --- | ---: |
| Canonically owned/equipped Shock gem; real `cast_group` bolt/nova/chain, mana, cooldown, trigger penalty, each chain target, later same-volley bolt benefit | 57 |
| Same-time ordering, equal-strength refresh, exact expiry boundaries, detached getters, menu pause | 11 |
| Zero damage, zero lightning with positive cold loss, birth protection, lethal hit, corpse cleanup, zero actual resource loss | 10 |
| All five post-mitigation components, armour order, real critical admission, final-resource leech/overkill, unchanged burn basis and both actors' DOT | 24 |
| Actual natural-end projectile explosion benefits from existing Shock but cannot attach or refresh it | 8 |
| Actual storm-skitter locked telegraph, original geometry/timing, 1.4D budget, hit, movement dodge, attack evasion, source death, player expiry boundaries | 26 |
| Pure attach/query/refresh/prune save bytes and RNG isolation; restart, town, active-map return, actual camp/boss/descendant map completion, profile switch, player death | 24 |

The existing monster resolver caps resistance at 90%; it does not expose a true lightning-immunity actor flag. The no-lightning case therefore suppresses lightning by exactly 100% through the real component modifier path while retaining positive cold damage. This verifies the attachment requirement without changing the existing resistance contract.

Initial execution is preserved as `gameplay-attempt1.log` and `gameplay-attempt1.json`. Its checks passed, but an unescaped literal percent sign in one test assertion label emitted five engine formatting errors. The only correction was `80%` to `80%%` in that formatted test label. The clean rerun above is the acceptance evidence.

Final main SHA-256: `46caab0bf99c917a6a22dee21fb4af5601dce0d772f704ac061b19f4bab84b7d`

Final test SHA-256: `f85de443504a1cf5863e62ee0f911e1e27dbf380c3c967b8dfff49c132327ecb`

Dedicated malformed temporal-batch and discarded-history preflight cases are owned by the separate main-integration suite. No production or UI files were changed by this gameplay test task.

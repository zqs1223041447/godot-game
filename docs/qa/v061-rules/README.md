# v0.61 Resolute Technique pure combat rules

Focused result: **651 checks, zero failures, process exit 0, no Godot error lines**, 0.439 seconds using Godot 4.6.3. This covers pure policy, compilation, attack admission and the actual private critical RNG. It does not claim main-scene, allocation, save, UI, Windows or long-run performance coverage.

- Passing log: `20261006-003128-rules.log.txt`
- Final counts and scope: `20261006-003128-result.json`
- Exact command, isolated environment, process status, elapsed time and tested-file SHA-256: `20261006-003128-receipt.json`
- Independent old-side source and transformed-file hashes: `fixture-provenance.json`

The first invocation (`20261006-003109-*`) stopped while parsing two test-local inferred Dictionary variables. No checks ran. Their types were made explicit; the next and only completed run passed. The production files did not change between invocations. Report counts include the final report-open check and agree with the terminal count; the six section counts total 650 and the report-open check is the remaining one.

## Contract

`resolute_technique` is one indivisible finite numeric zero/one flag. It does not assemble from two independently equipped effects. `CombatData.snapshot` writes numeric `1.0` only when enabled, omits absent/zero, and preserves malformed source values for explicit compiler rejection. Mutable malformed inputs are deep copied.

`ResoluteTechniqueRules.active(snapshot)`, `snapshot_error(snapshot)` and `compiled_profile(snapshot)` provide the pure shared contract. The compiled top-level `hit_policy` exists only when enabled and contains exactly `id: resolute_technique`, `hits_cannot_be_evaded: true` and `cannot_deal_critical_strikes: true`. Execution uses the snapshot's frozen numeric flag and compiled critical profiles; presentation fields are independent copies.

Critical compilation completes the original input and derived-profile validation first. It retains the validated potential multiplier for inspection and sets all primary and independent-secondary chances to zero, including attacks and spells. With no critical source, enabled hit profiles explicitly contain chance 0 and potential multiplier 1.5. Actual rolls always return noncritical with multiplier 1. Utility skills do not gain a hit critical profile.

`AttackHitRules.resolve(accuracy, evasion, entropy = 50.0, hits_cannot_be_evaded = false)` keeps the original return shape. Its enabled branch still validates accuracy, evasion and entropy, then returns chance 1, hit true and the exact input entropy. Range, line of sight, spawning, target life, payment and capacity belong to the existing callers and are outside this pure admission function.

Neither `critical_strike_runtime.gd` nor `projectile_runtime.gd` changes. The existing zero-chance freeze path performs no private random draw, records no critical event, and clears any inherited `critical_roll` on a detached copy. Enabled casts intentionally differ from ordinary positive-chance casts in private critical RNG use; this is not a claim that allocating the node preserves before/after private RNG state.

## Evidence

- 46 flag checks: exact zero/one acceptance; bool, string, null, collection, NaN, infinity, negative, fractional and out-of-range rejection; absent/zero snapshot bytes; detached invalid collections
- 136 critical validation checks: original invalid base/scope fields and excessive derived multipliers preserve old failure returns; all attack/spell/melee/projectile/chain scopes; sample zero and upper boundary; independent secondary; no-source case
- 287 compiler checks: all ten skills plus basic projectile and basic melee, both plain and populated critical sources; targeted ignite/shock support cases; complete old/zero cast bytes; packets, recipes, payment and cooldown; primary/secondary profiles; frozen-cast re-entry rejection
- 125 attack checks: accuracy zero/normal/high, evasion zero/normal/high, entropy zero/mid/upper boundary; invalid numeric values and entropy boundary; exact legacy returns and exact future ordinary admission after entropy bypass
- 49 private RNG checks: independently frozen old/runtime roll results and checkpoints across primary/secondary, explicit zero continuation, no-draw enabled freezes, inherited-roll cleanup, future ordinary stream continuation, guaranteed-critical legacy behavior
- 7 isolation checks: caller input, display policy, display critical profile, already-created old/enabled casts and detached descendants remain independent of later source changes

These section counts include one explicit completion assertion each, so a section-level script exception cannot quietly masquerade as a completed pass. Scene-level range, line of sight, payment, spawning, death, capacity, allocation/refund and actual projectile descendant paths are covered separately by the integration owner.

## Independent legacy oracle

The old compiler, CombatData, critical rules/runtime and attack rules come from commit `b389993ed7f7a90f4043c668704583d44b22f343`. Their recursive GDScript preload/load closure contains 27 frozen files (158,981 original source bytes). Every closure dependency, including skill data, supports, damage assembly and weapon-local validation, resolves to a frozen file under this directory. The only transformations are removal of global `class_name` declarations and replacement of these dependency paths. The old side does not call the current compiler or rules indirectly.

The provenance manifest stores original and transformed SHA-256 hashes for each file. Complete rule and compiler comparisons use `var_to_bytes`, preserving types, structure, key order and numeric values rather than checking a subset of fields.

## Reproduce

After the project's shared headless import, run from its root:

```sh
XDG_DATA_HOME=/tmp/godot-m1-v061-rules/data \
XDG_CONFIG_HOME=/tmp/godot-m1-v061-rules/config \
XDG_CACHE_HOME=/tmp/godot-m1-v061-rules/cache \
RESOLUTE_RULES_REPORT=/tmp/v061-resolute-rules-result.json \
godot --headless --path . --script res://tests/resolute_technique_rules_test.gd
```

Require exit 0, zero failures and no `SCRIPT ERROR:` or `ERROR:` log lines. The pure test performs no save or account changes.

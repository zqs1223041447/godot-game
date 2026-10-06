# Single-fire monster settlement candidate

Production base: v62 b93018005413444ad6f988974f4ef3ea09902c5e. The only gameplay change is in `scripts/mechanics/defense_rules.gd`: validated ordinary monster burns with numeric-zero mana ratio/max-fire bonus directly construct the same receipt instead of constructing then revalidating its own known single-fire packet. General public settlement and all other options remain. The existing planning-rate query calls this same public burn method and benefits from identical cheaper receipt creation; its math, order and prediction contract did not change. No prior rate helper, scheduler rewrite, scalar status projection, new cache or feedback interface was revived.

## Exact gate

`../v063-settlement-rules`:58,593 checks,0 failures, including58,546 full `var_to_bytes` return comparisons against independently frozen v62 and its DamageResolver. Covers negative zero (`total=+0.0; total+=amount`), exact numeric expression order, StringName actor/stage keys, typed detail arrays, all receipt fields, shield/life/overkill, detached outputs, invalid parameter precedence, and nonzero/player/cap fallbacks. Initial candidate used String actor/stage keys instead of the original StringName keys; that was fixed by original property assignment. A subsequent one-check failure was only the test's independent key-order expectation still using String; only that test expectation changed before the final passed batch. Original logs/results are retained.

## Unwrapped actual scene comparison

The same external harness loads each project's own production Main/Model/BurnRuntime. There are no timing subclasses. All499 frozen-v62 production files were verified before/after. The candidate differs only in DefenseRules. Every process has fresh isolated XDG and original actors/AI/attacks. The player is protected as a sampling fixture;100catalog monsters and180controlled runtime carriers do not claim a natural player fires180 every frame.

| Case | Before mean / median / p95 / peak ms | Candidate mean / median / p95 / peak ms |
|---|---|---|
| no-burn24ticks |52.482 /51.453 /63.996 /71.601|51.052 /49.479 /65.708 /71.942|
| one initial volley then150ticks death/propagation |45.278 /12.432 /148.306 /635.268|34.849 /8.709 /118.826 /564.997|

The death case mean decreases23.0%, median29.9%, p9519.9%, peak11.1%. The no-burn control has no call to the modified branch; its small mixed differences (mean-2.7%, p95+2.7%, peak+0.5%) are reported, not marketed as an improvement. The baseline and candidate each retain27 eligible root rewards. Full per-frame samples and threshold counts are in the JSON files. Pure6000-call timing is only a separate function-level signal, not a whole-game claim.

Before and after fully serialized observations are exactly equal without projections: no-burn29,154,664bytes/SHA25667b59a8dbe484f78859579b42708f2a092f8e923c9c038b5b61723ceba1a4dba; death109,388,768bytes/SHA2568e3ea9b53c6ed033c5f15b9286118332241b4f4ab08139ab816c4af2da79b2a3. This covers each tick's actors/carriers, queues/root lineages, burn state and identity-cache state, clocks/expiry, traces, resources, feedback queues, effects, model, RNG/private critical, save counts and disk bytes. Actual final save files also match exactly. Observation construction/serialization is outside the tick timer on both sides. Compressed records restore original bytes; raw originals remain locally.

The first no-burn pair completed but full observations exposed three random startup rings created by restart before fixed-seed population setup. The old diagnostic hadn't observed those rings. Original files/harness remain in `first-startup-rings`. Read-only inspection showed all non-ring fields were identical; that diagnostic omission is not final acceptance. The corrected fixture clears effects belonging to discarded pre-seed actors before starting the controlled scene. Final comparisons include all rings and use no projection. Only the previously invalid pair was rerun; the death pair then ran once. Production code was not changed by this fixture fix. Error-monitoring runner terminates immediately on engine/script errors; timeout values are safety bounds, not required waits.

These bounded cloud headless CPU measurements are not Windows hardware FPS or rendering results. Residual peak is still approximately565ms and the no-burn scene remains around51ms, so this is not a claim all crowd stutter is solved. No actor reduction, attack disabling, reward omission, delayed settlement, GUI/visual gate,600-second test, or historical full-suite rerun.

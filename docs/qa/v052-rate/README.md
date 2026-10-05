# v52 checked effective-rate experiment (not a release)

Baseline: published v51 d6684d. Only main.gd death prediction and DefenseRules change. The predictor needs effective DPS but formerly built a complete settlement against fictitious zero shield/one health. burn_rate reuses its fresh validated profile container, preserving amount/actor/resistance validation and raw*(1-resistance) order. Its damage_total retains the original single-component accumulation from positive zero, including signed-zero behavior. Real incoming_burn still calls the original settle_resolved with exactly the original resolved envelope.

All event ordering, death_at expression, next-ULP fix, positive-width integration, exact_deaths residual handling, target order, death/transfer flushes, rewards and RNG sites remain unchanged. No cache, scheduler, actor-count or UI changes.

Initial independent frozen-Defense differential:163 cases/783checks, exit0. Covers exact full settlement bytes, dummy-settlement rate bytes, negative zero/subnormal/large finite inputs, caps, malformed inputs with simultaneous-invalid priority, detached profiles and global RNG. These establish rule equivalence; performance and real-main equivalence remain pending in this work-in-progress checkpoint.

## Initial real-main samples

Both Ember observations and saved files match byte-for-byte; no_burn and ordinary ignite controls also match their fresh v51 baseline and retained v50 observations. Main's entire source differs only in the one planning call; death_at, next-ULP, positive segment loops, exact_deaths, transfer, and reward ordering remain textually identical. Final observations contain exact final actors/carriers/statuses, traces and RNG/save; they are not an all-frame trace archive.

Mean controlled high-collision680.463→619.673ms(-8.9%); death-spread41.535→37.417ms(-9.9%),p95 144.461→111.794ms,max682.945→549.307ms. No-burn51.017→51.062ms; ordinary ignite100.298→104.076ms(+3.8%). All8 short commands exit0/noERROR. Timing order is declared in comparison-initial.json; one control is not proof of a causal regression or statistical significance. Extra profile fields on real settlements are a possible source of overhead; the experiment is not accepted as a release at this stage.

## Final disposition: not shipped

The second variant keeps the real-settlement profile unchanged and shares only the pure float multiplication. Its163cases/783checks passed exactly. Final high-collision mean680.463→579.895ms(-14.8%); death-spread41.535→37.539ms(-9.6%). However ordinary ignite100.298→106.605ms(+6.3%),p95 111.216→130.363ms. This repeats the direction of the initial ordinary control, so the candidate is withdrawn rather than claiming general improvement. Small serial samples do not prove a causal regression on all machines.

Main and DefenseRules have been restored byte-for-byte to published v51. Initial and second patches, commits, frozen oracle, logs and full comparisons remain for recovery. No third variant, version bump, export or Release was created. Other v51 source is unchanged. The no-burn control was not rerun for the second variant: it creates no burning state or burn-rate call; its previous complete output remains unchanged.

All three second-round final observations and actual saves match their frozen baselines exactly. This is an equal-behavior experiment rejected on measured performance risk, not a correctness failure. Test files and783checks describe the archived candidate; they are not assertions that the restored production exposes burn_rate.

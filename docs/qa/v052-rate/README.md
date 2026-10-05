# v52 checked effective-rate experiment (not a release)

Baseline: published v51 d6684d. Only main.gd death prediction and DefenseRules change. The predictor needs effective DPS but formerly built a complete settlement against fictitious zero shield/one health. burn_rate reuses its fresh validated profile container, preserving amount/actor/resistance validation and raw*(1-resistance) order. Its damage_total retains the original single-component accumulation from positive zero, including signed-zero behavior. Real incoming_burn still calls the original settle_resolved with exactly the original resolved envelope.

All event ordering, death_at expression, next-ULP fix, positive-width integration, exact_deaths residual handling, target order, death/transfer flushes, rewards and RNG sites remain unchanged. No cache, scheduler, actor-count or UI changes.

Initial independent frozen-Defense differential:163 cases/783checks, exit0. Covers exact full settlement bytes, dummy-settlement rate bytes, negative zero/subnormal/large finite inputs, caps, malformed inputs with simultaneous-invalid priority, detached profiles and global RNG. These establish rule equivalence; performance and real-main equivalence remain pending in this work-in-progress checkpoint.

## Initial real-main samples

Both Ember observations and saved files match byte-for-byte; no_burn and ordinary ignite controls also match their fresh v51 baseline and retained v50 observations. Main's entire source differs only in the one planning call; death_at, next-ULP, positive segment loops, exact_deaths, transfer, and reward ordering remain textually identical. Final observations contain exact final actors/carriers/statuses, traces and RNG/save; they are not an all-frame trace archive.

Mean controlled high-collision680.463→619.673ms(-8.9%); death-spread41.535→37.417ms(-9.9%),p95 144.461→111.794ms,max682.945→549.307ms. No-burn51.017→51.062ms; ordinary ignite100.298→104.076ms(+3.8%). All8 short commands exit0/noERROR. Timing order is declared in comparison-initial.json; one control is not proof of a causal regression or statistical significance. Extra profile fields on real settlements are a possible source of overhead; the experiment is not accepted as a release at this stage.

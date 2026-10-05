# v52 checked effective-rate experiment (not a release)

Baseline: published v51 d6684d. Only main.gd death prediction and DefenseRules change. The predictor needs effective DPS but formerly built a complete settlement against fictitious zero shield/one health. burn_rate reuses its fresh validated profile container, preserving amount/actor/resistance validation and raw*(1-resistance) order. Its damage_total retains the original single-component accumulation from positive zero, including signed-zero behavior. Real incoming_burn still calls the original settle_resolved with exactly the original resolved envelope.

All event ordering, death_at expression, next-ULP fix, positive-width integration, exact_deaths residual handling, target order, death/transfer flushes, rewards and RNG sites remain unchanged. No cache, scheduler, actor-count or UI changes.

Initial independent frozen-Defense differential:163 cases/783checks, exit0. Covers exact full settlement bytes, dummy-settlement rate bytes, negative zero/subnormal/large finite inputs, caps, malformed inputs with simultaneous-invalid priority, detached profiles and global RNG. These establish rule equivalence; performance and real-main equivalence remain pending in this work-in-progress checkpoint.

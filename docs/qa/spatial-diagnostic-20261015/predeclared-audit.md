# Next frame-cost audit — 2026-10-15

Read-only source audit at local `7c4b3fd7ddeec9fecd7396c80573c332bb47a4e0`. No production edits, Godot runs, benchmark reruns, or external writes performed. Existing untracked engine sidecars were left untouched.

## Decision

One genuinely distinct **diagnostic hypothesis** is justified: redundant spatial-index remove/reinsert work after monster movement when its conservative occupied-cell footprint has not changed. This is a possible small recurring AI improvement, **not evidence of a solution to the residual ~550 ms burn frame**. No new high-impact burn optimization is justified by the existing profiles alone.

## Code and mechanism

- `scripts/main.gd:1043–1044`: rebuild enemy spatial index each enemy-update pass.
- `scripts/main.gd:1075–1096`: query separation in original index order, move/clamp/resolve terrain, then call `enemy_spatial.update(enemy_index)` for every non-spawn-protected living actor, even if it stayed still or moved within its existing cells.
- `scripts/combat/spatial_target_index.gd:49–59`: each update unconditionally removes and reinserts every reference alias.
- Same file `104–126,129–135`: remove erases bucket entries, erases empty buckets and clears memberships; insert validates the live actor, recomputes conservative bounds and repopulates arrays/dictionaries.
- Same file `62–76`: query results deduplicate by original array index and explicitly sort ascending, so private bucket insertion order does not determine collision/separation order.
- Same file `138–158`: exact rounding margin, invalid/overflow fallback and operation bounds are contractual. A potential no-op must compare the newly validated conservative cell footprint against existing memberships; position equality alone or approximate movement quantization is insufficient.

This would avoid structural index churn, not collision checks or movement. All live positions/radii still feed narrowphase. Alias updates and resized-source rebuilding must remain intact. No additional persistent lookup cache is needed: existing memberships already describe the index contents.

## Existing evidence and limits

- `docs/qa/v050-density/allocation-no_burn.json`, row 0: instrumented enemy AI mean 2,743.875 us, maximum 3,197 us; projectile phase mean 48,572.542 us. Thus even eliminating the entire historical AI phase would not remove this control's main cost. Spatial update itself was not timed separately.
- `docs/qa/v023-repair/after-headless-100-crowd-120.json`, first 600-tick bucket: AI mean 2,957.317 us out of tick mean 3,743.373 us in a 100-actor no-projectile crowd. Historical crowd evidence makes the AI path worth a narrow diagnostic, but is not a current performance estimate.
- `docs/qa/v095-profile/README.zh-CN.md`: 20-frame ember advancement 3,719.432 ms / instrumented tick 4,688.015 ms (79.34%); peak frame has no kills. That is an independent dominant cost and must not be attributed to spatial maintenance.
- `docs/qa/burn-state-copy-20261015/README.md`: accepted limited shallow private state optimization retains peaks 562.692/552.879 ms. Control variability is material.
- `docs/qa/burn-prediction-cache-20261015/README.md`: prediction cache rejected on both no-burn control regressions. Do not revive it or use favorable one-mode timing as acceptance.

The new mechanism differs from the earlier 128→64 enemy cell-size change, existing projectile broadphase/index rebuilding, projectile work-order cache, hit lookup, trace-copy optimization, private BurnRuntime state copy, scalar defense/feedback proposals, and predicted-rate caching. It does not change cell size, public runtime interfaces, burn state or event chronology.

## Minimal isolated experiment (not run)

1. Freeze current Main and SpatialTargetIndex hashes; create temporary diagnostic copies only. Use the current 100-catalog-monster/180-projectile short harness with all AI, geometry, attacks and burn semantics enabled. Begin with one clean and one instrumentation-only 20-tick no-burn run, fresh XDG directories and a 90-second watchdog each, in an exclusive CPU window. Preserve full observations/final-save bytes and hash copied source before/after. Do not invoke historical generators that overwrite evidence.
2. Instrument only the enemy index instance (not the projectile index). Record per-frame update/alias counts, actual old/new footprint equality, overflow transitions, bucket removals/insertions, and separate update-inclusive time. Preserve original mutation behavior during this diagnosis. Count same-footprint opportunity using a separately reported diagnostic window; do not treat its overhead as removable production cost.
3. Stop after this diagnosis if structural index work is negligible or same-footprint cases are rare. In particular, do not pursue this as PERF-001 peak remediation: the historical AI budget is already too small. Only if structural update accounts for at least 20% of AI time and at least half of updates are same-footprint should a single no-op candidate be considered for ordinary crowd CPU improvement.

## Candidate acceptance gate, only if diagnosis clears

- Semantic: original-vs-candidate exact ordered query outputs after every sequential move; same-reference actors at multiple indices, distinct actors with duplicate IDs, source resize, invalid update indices, stationary actors, same-cell movement, boundary crossings with rounding margins, radius changes, invalid/nonfinite/negative radii, overflow entry/exit, and terrain-clamped movement. New bounds must undergo the same validation before any early return. Internal bucket insertion order may differ; all observable query order and narrowphase/game state must be identical.
- Integration: full typed per-frame observations, final observation and actual saved bytes identical against frozen current production, including actors, position/resource floats, projectile events, RNG, all traces, rewards and clocks. Reuse focused spatial differential tests and the short full observer; no weaker projected/rounded comparison.
- Timing: predeclare two reversed-order clean pairs per no-burn, ignite and ember mode, 20 ticks each; no instrumentation in candidate-acceptance timing, no favorable extra variants. Require no-burn AI mean improvement in both pairs and pooled >=10%; whole no-burn tick pooled improvement >=1%. Reject if either burn control mean or peak regresses >3% in both pairs or >5% pooled, or any semantic check fails. Report every raw sample and the limited expected absolute benefit. If timing is inconclusive, retain no production change.

No benchmark was launched to establish these thresholds or outcomes; these are a proposed gate, not completed verification. No Windows FPS claim follows.

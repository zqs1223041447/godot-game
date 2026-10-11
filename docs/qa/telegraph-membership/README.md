# Telegraph membership query (base b8cb93c)

## Scope and invariant

Replace only Main's two boolean `state_for(id).is_empty()` consumers (enemy pursuit hold and end-of-tick admission) with `has_state(id)`. The scheduler stores a nonempty attack only at successful admission; cancellation, source invalidation, expiry and reset erase it. `state_for` deep-copies and adds presentation fields but never changes emptiness or runtime state. Its snapshot/copy behavior is unchanged. No persistent cache or new scheduling branch is introduced.

This removes unnecessary nested copies for active actors and empty-dictionary snapshot construction for inactive actors. In a 100-actor crowd, the two callsites can perform up to 200 such queries per simulation tick, depending on their existing eligibility gates. This is a query CPU/allocation optimization, not an FPS or rendering result.

## Executed focused checks

Godot 4.6.3, Linux, headless, isolated XDG data/config/cache under `/tmp/godot-telegraph-membership/`:

- `tests/telegraph_membership_test.gd -- --bench`: 6,655 checks, zero failures. Compares the new query to the unchanged prior snapshot predicate, including missing/negative IDs, ordinary/three boss patterns, partial freeze steps, warning/recovery/expiry, cancellation, dead/removed sources, reset, 100 active and mixed populations. Byte snapshots verify queries and benchmark do not change scheduler state or attack identity.
- `tests/telegraph_membership_main_test.gd`: 183 checks, zero failures. Two detached Main instances execute the actual movement and admission functions over 180 frames/100 initial actors. The oracle scheduler overrides only the new query with the released snapshot predicate. Per-frame byte comparison covers enemies, scheduler, traces, event counts, RNG, resources, burn state and separation counters, with death/removal/cancel/reset transitions. Both admit and resolve attacks. Synthetic actors and player invulnerability isolate these callsites; this does not claim damage settlement, UI, full-loop or rendered equivalence.
- `git diff --check`: clean.

Commands (run each with all three XDG variables pointing into the isolated directory above):

```
godot --headless --path . --script tests/telegraph_membership_test.gd -- --bench
godot --headless --path . --script tests/telegraph_membership_main_test.gd
```

Raw successful outputs are adjacent to this file. Each benchmark case warms both paths, alternates pair order for six pairs, and uses 10,000 queries per sample. Timings are recorded without a performance pass/fail threshold. Dense active samples: snapshot 27,916–29,442 µs versus membership 1,680–1,741 µs; mixed samples: 17,046–18,004 versus 1,495–2,156 µs; empty samples: 5,756–6,215 versus 1,320–1,936 µs. These are local microbenchmark measurements, not whole-frame improvements.

## Known unrelated test limitation

The existing `tests/telegraph_integration_test.gd` was also attempted, and is **not a pass**: it reported 63 checks / 5 failures plus script errors. It explicitly injects legacy `scripts/build_state.gd` into current Main, which now calls absent `normal_journey`, `normal_pending_rewards` and `invalidate_gem_trade_quotes`. The fixture mismatch is visible in the pre-change sources as well. This patch does not repair that older integration fixture. No full suite, cloud setup, network operation, export or rendered check was performed.

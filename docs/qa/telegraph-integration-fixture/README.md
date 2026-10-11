# Canonical telegraph integration fixture

Base: `5b700a7`. Date: 2026-10-11 UTC. Test-only repair; no production changes.

## Why the old fixture failed

`tests/telegraph_integration_test.gd` injected legacy `BuildState` into current Main. Main and its HUD now require canonical APIs such as `normal_journey`, `normal_pending_rewards` and `invalidate_gem_trade_quotes`. Main also starts in safe town: combat ticks return early there, and the practice demo entrypoints reject that world mode. Consequently, the previous fixture did not actually exercise its promised full-loop birth/warning/recovery assertions.

A second stale expectation assumed all ember-guard fire damage settled upfront. Current `BurnRules.ENEMY_POLICY` applies a 0.5 upfront-fire multiplier and attaches a three-second burn with rate fraction 1/3 of that upfront fire. For a 1.4-multiplier, 50/50 physical/fire attack, physical stays `damage * 0.7`, upfront fire is `damage * 0.35`, and the remaining lifetime raw burn budget is `damage * 0.35`.

## Exact fixture changes

- Retain Main's real `CanonicalGameState`; remove the legacy-state injection. No fake methods, compatibility subclass or production changes.
- Enter practice through the actual `leave_normal_town(world_context().revision)` transition and assert success and world mode. This exercises canonical save/admission under isolated temporary storage, rather than assigning a private mode or bypassing the world gate. Fail immediately if admission is refused.
- Keep the original timing, physical damage, collision boundary, source snapshot, contact, movement, pause, cancellation, reset, simultaneous-hit, capacity and death assertions.
- Replace only the obsolete upfront-fire expectations with the authored current split. Add assertions that the real player hit passes canonical accuracy/evasion admission, attaches the same source's burn, and retains the remaining fire budget.
- Strengthen mutated-source coverage: frozen packet contains no cold; an inside hit attaches the original fire burn; an outside hit attaches none. No catalog enemy stats or canonical player defenses are replaced.

This is the current canonical **arena-practice** integration contract. The two legacy-named demo reset entrypoints genuinely require practice mode, and remain covered in that supported world. This does not claim formal-map admission/completion, historical legacy-BuildState compatibility, or rendered/UI-layout coverage.

## Bounded verification

One before run and one after run, Godot 4.6.3 official, Linux headless, each with separate empty XDG data/config/cache roots:

```
timeout 60s env \
  XDG_DATA_HOME=/tmp/godot-telegraph-fixture-before/data \
  XDG_CONFIG_HOME=/tmp/godot-telegraph-fixture-before/config \
  XDG_CACHE_HOME=/tmp/godot-telegraph-fixture-before/cache \
  godot --headless --path . --script tests/telegraph_integration_test.gd

timeout 60s env \
  XDG_DATA_HOME=/tmp/godot-telegraph-fixture-after/data \
  XDG_CONFIG_HOME=/tmp/godot-telegraph-fixture-after/config \
  XDG_CACHE_HOME=/tmp/godot-telegraph-fixture-after/cache \
  godot --headless --path . --script tests/telegraph_integration_test.gd
```

- Before: exit **1**, **63 checks / 5 failures**, **70 script errors**, plus leaked-resource diagnostics. Full raw output: `before.txt`.
- After: exit **0**, **81 checks / 0 failures**, **no script errors, errors or warnings**. Full raw output: `after.txt`.
- `git diff --check`: clean.

The count increase includes previously interrupted full-tick assertions that now execute, plus eight new assertions. No assertions were removed to obtain a pass. The three changed numeric expectations track the implemented burn split while newly checking the remainder instead of discarding it.

No full suite, network/cloud action, rendered check, export, commit or push was performed.

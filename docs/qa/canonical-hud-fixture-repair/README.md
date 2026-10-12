# Canonical HUD F1 fixture admission repair

2026-10-11 · Godot 4.6.3 headless · production HEAD `a1f6de404cf5f368b601c79f86032d215196ac59`

Only `tests/canonical_hud_integration_test.gd` changed. No production input handler, binding, skill, projectile, mana, cooldown or menu logic changed.

## Diagnosis

The fixture successfully moves five owned supports and binds `group_000002` to F1 through the actual canonical skill panel. Main starts in formal town. Closing the two docks resumes input but does not leave town. The real `_unhandled_key_input` resolves F1 through `state.group_for_key` and calls `cast_group`, whose explicit town/map-complete guard refuses combat. This is intentional safe-area behavior, already present in root commit `fd07282`, rather than an F1 or font-scaling regression. Historical font QA on `b2ca0277` reports the same 2418/1 failure; this repair independently reproduced it on the production HEAD above.

## Minimal repair and strengthened checks

The test now verifies safe-town refusal first, then uses public `leave_normal_town` with the current world revision. It disables autofire and retains the existing held Main simulation, making the input assertions deterministic. Every F1 attempt still uses `root.push_input(event, true)` plus real frame dispatch; no direct cast/handler invocation or synthetic projectile is used.

The original five-projectile and positive-cooldown assertion remains unchanged. Twelve added assertions cover:

- Valid five-link compiled recipe, positive mana/cooldown; starting town and side-effect-free safe-area rejection; successful public arena admission
- Ready group blocked by a real pause panel, no mana/debt/projectile changes, and input eligibility restored by closing it
- Ready group with zero mana cannot acquire debt or fire
- Successful F1 spends exactly compiled mana and starts exactly compiled cooldown
- Immediate repeated F1 cannot fire or charge twice
- Accepted/rejected input preserves canonical snapshot and exact saved bytes

All inventory/discard, support-binding, double-Escape, source-tree, 2387-node containment, talent allocation/refund and viewport assertions are retained. This is controlled headless integration, not natural gameplay or screenshot evidence.

## Evidence and limits

- `before.log.txt`: 2418 assertion executions, 1 failure, exit 1
- `after.log.txt`: 2430 assertion executions, 0 failures, exit 0; no SCRIPT ERROR / ERROR / FAIL
- `git diff --check`: pass
- README reproduction snippet: `bash -n` pass

Counts are assertion executions, mostly per-node checks, not independent scenarios. Only this focused script was run. No full suite, GUI, export, network operation or commit. This does not newly cover cooldown expiry, input echo/key-release behavior, different dynamic bindings, gamepad input, combat under advancing simulation, save failures or visual appearance. Neither broad canonical-group tests nor historical font QA are claimed as rerun.

## Reproduce with isolated data and strict failure status

From the repository root:

```sh
(
  isolated=$(mktemp -d /tmp/godot-m1-canonical-hud.XXXXXX) || exit 1
  status=0
  XDG_DATA_HOME="$isolated/data" XDG_CONFIG_HOME="$isolated/config" \
  XDG_CACHE_HOME="$isolated/cache" timeout 90 godot --headless --path . \
    --script res://tests/canonical_hud_integration_test.gd > "$isolated/run.log" 2>&1 || status=$?
  cat "$isolated/run.log" || exit 1
  [ "$status" -eq 0 ] || exit "$status"
  scan_status=0
  grep -nE 'SCRIPT ERROR:|ERROR:|FAIL:' "$isolated/run.log" || scan_status=$?
  [ "$scan_status" -eq 1 ] || exit 1
)
```

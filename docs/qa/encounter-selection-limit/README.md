# Challenge selection cap recovery

Verified in the dot Linux checkout based on `fd07282`, Godot 4.6.3, 2026-10-10 UTC.

## Scope

The pause-menu challenge picker offers six choices with a two-choice limit. Previously, toggling a third choice passed an invalid draft into `set_context`, erased the accepted choices, and disabled the entire picker. The UI now disables only unselected choices at the cap and explains how to replace a choice. A defensive toggle guard preserves the accepted draft even if a disabled checkbox's signal is invoked directly. Selected choices and confirmation remain usable.

External invalid `set_context` inputs still fail closed. Owner locks retain priority. No encounter rules, model, rewards, saves, graphics layout, or telegraph renderer changes.

## Evidence

- `before.log`: focused regression against original control, 34 checks / 14 failures
- `after.log`: same focused regression against changed control, 34 checks / 0 failures
- `main.log`: current canonical Main scene, real pause panel and restart-confirmation controls, 8 checks / 0 failures
- `legacy-integration.log`: existing `encounter_ui_integration_test.gd`, 64 checks / 3 failures plus script errors. This test injects legacy `BuildState` into current Main, which requires absent methods including `normal_journey`, `normal_pending_rewards`, and `invalidate_gem_trade_quotes`. It is not counted as passing; no claim that this change repairs that fixture
- `new-text-font.log`: every character in the new tooltip is mapped by the bundled font
- `font-coverage.log`: wider font audit failed on other runtime strings outside this patch; no new tooltip glyph is missing
- `git diff --check`: passed

These are headless tests, including programmatic control interaction in the actual Main scene. No native visual/screenshot or Windows verification was performed. No layout/artwork changed.

## Reproduce

Run from the project directory:

```sh
export XDG_CONFIG_HOME=/tmp/godot-dot-migration/config
export XDG_CACHE_HOME=/tmp/godot-dot-migration/cache
XDG_DATA_HOME=/tmp/godot-dot-encounter-limit-after-log timeout 20s godot --headless --path . --script res://tests/encounter_selection_limit_test.gd
XDG_DATA_HOME=/tmp/godot-dot-encounter-limit-main-log timeout 40s godot --headless --path . --script res://tests/encounter_selection_limit_main_test.gd
XDG_DATA_HOME=/tmp/godot-dot-encounter-limit-legacy-log timeout 40s godot --headless --path . --script res://tests/encounter_ui_integration_test.gd
python3 tools/check_font_coverage.py
```

The before regression was first run directly before editing production code and reproduced 14 failures. For the retained log it was rerun without swapping the working-tree file: `git show fd07282:scripts/ui/encounter_controls.gd` was copied to `/tmp/godot-encounter-controls-before.gd`, removing its `class_name` line to avoid collision with the imported project class. A temporary copy of the focused test preloaded that absolute path. The unchanged tooltip helper reference resolves to the project class; no tooltip construction is exercised by this state regression. Command:

```sh
XDG_DATA_HOME=/tmp/godot-dot-encounter-limit-baseline-log timeout 15s godot --headless --path . --script /tmp/godot-encounter-limit-before-test.gd
```

Coverage includes repeated selection/removal, forced over-limit callbacks, confirmation of the retained draft, replacing a choice, clearing back to ordinary encounter, invalid external context, owner locks, recovery with valid context, canceling the actual Main confirmation, reopening the pause panel, and unchanged canonical state/run revision/RNG during draft operations.

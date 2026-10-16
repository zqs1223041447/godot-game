# Canonical encounter UI fixture — 2026-10-15

## Scope

Base: `adf183f` on `dot/20261015-encounter-fixture`. Only `tests/encounter_ui_integration_test.gd` and this report change. No production, balance, save-format, input-routing, or encounter-admission changes.

## Diagnosis

The preceding [current Help verification](20261015-current-help.md) reproduced the old encounter integration test's **64 checks / 3 failures** with both changed and unchanged HUD. Its logs also showed missing canonical APIs (`normal_journey`, `normal_pending_rewards`, `invalidate_gem_trade_quotes`) because the test replaced Main's state with legacy `BuildState` before scene initialization.

Two assumptions had become invalid:

1. Main now starts in formal town with `CanonicalGameState`. `Main.start_encounter` accepts only `normal` (arena practice). The old fixture neither provided the required canonical world APIs nor entered practice. Confirmation therefore could not legitimately start the selected run; ordinary retry could not retain an uncommitted selection.
2. `DockedMenuState.request("inventory")` intentionally rejects dock navigation while an overlay is open. Calling it from pause does not navigate away. The old cancellation assertion therefore tested an event that never occurred. Settings is a supported pause-to-overlay transition, exposed by the real `VisualSettingsButton`.

These explain the target test's failures without a verified production defect.

## Repair and retained coverage

- Instantiate the real Main scene without replacing its canonical model. Verify formal town, call `leave_normal_town` with the current world revision, and verify actual practice mode before recording the state/save baseline.
- Keep checkbox toggles, the component's confirm signal, dialog cancel/confirm signals, duplicate confirmation, reopened selection, context rebuild, ordinary retry and stale-run checks. No direct writes to encounter IDs, pending confirmation fields, world mode, or canonical snapshot are used to manufacture success.
- Keep the inventory request and explicitly check that it preserves the pending pause request. Then activate the actual pause Settings button, verify the route changed, and retain the original navigation-cancellation and stale hidden-dialog assertions.
- Keep both resolutions (1280×720 and 2560×1440), font scales 1.0/1.2, corresponding UI scales 1.0/1.1, focus colors, scroll width, tooltip text/wrapping, dialog bounds and theme checks. Require each resized dialog to actually be visible before measuring it.
- Check canonical snapshots and both normal/test save-file bytes for unchanged state after UI operations. The supported initial world transition is allowed to save; the comparison baseline is taken afterward.
- Add fail-fast fixture/control/transition checks, verify ordinary retry increments the run revision, and add a 60-second SceneTree watchdog. Each process also has a 90-second external timeout.

This is **headless signal-path integration and logical-layout verification**, not native mouse/keyboard input or screenshot/pixel acceptance. It preserves the original signal-driven interaction coverage; no native-input claim is made.

## Reproduction

Godot `4.6.3.stable.official.7d41c59c4`, Linux headless. Use a fresh isolated directory for every suite; no editor import command is required:

```sh
suite=encounter_ui_integration_test
base=$(mktemp -d /tmp/godot-encounter-fixture-XXXX)
mkdir -p "$base/cache"
XDG_DATA_HOME="$base/data" XDG_CONFIG_HOME="$base/config" \
XDG_CACHE_HOME="$base/cache" timeout 90s godot --headless --path . \
  --script "tests/$suite.gd"
```

Results:

- `encounter_ui_integration_test.gd`: **88 checks, 0 failures**, exit 0, no script errors
- `current_help_contract_test.gd`: **165 checks, 0 failures**, exit 0, no script errors
- `git diff --check`: clean

## Adjacent-suite finding, outside this patch

An additional `encounter_controls_test.gd` run exits 1 with **1023 checks, 9 assertion failures**: five `Preview matches the current compiler factors` assertions and four `Locked narrow view stays compact with wrapped text` assertions. The former requires both aggregate factor strings even for empty/single selections; the current component renders selected definition descriptions. The latter hard-codes a total component height under 500 pixels. This independent test and all its production dependencies are unchanged by this patch; it does not load the repaired integration test. No claim of a fully green encounter test family is made, and these separate expectations are not repaired here.

## Viewport clarification (2026-10-15 follow-up)

The 1280×720 and 2560×1440 values above are requested physical root-window sizes. Under this project’s canvas_items stretch configuration, the tested Main scene retains a 1280×720 logical viewport (HUD local size also changes with UI scale). These checks do not establish an independent 2560×1440 logical layout or native rendered 2K acceptance. The later keyboard-scroll regression explicitly records and asserts the actual logical viewport.

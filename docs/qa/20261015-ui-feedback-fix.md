# Canonical UI feedback and discard lifecycle regression

Date: 2026-10-15. Scope: canonical skills/inventory panels only. No schema, art, reward, balancing, or content additions.

## Behavior

- Each completed panel request replaces previous feedback. A persisted success says `操作已保存`; the established `error_code: no_change` result says `无需更改`, without pretending that a save occurred. Other failures continue to show the model's reason.
- A model revision change proactively consumes a pending discard and hides its dialog before emitting cancellation feedback. This ordering prevents synchronous feedback listeners or late confirmation signals from acting on the old request.
- The model's revision check remains an independent defense against an explicitly retained stale request. Cancel, panel hide, save-failure rollback, and fresh retry retain their contracts.

## Reproduction / validation

Godot 4.6.3, Linux headless, existing imported project assets. No editor/import operation. Each process uses separate temporary XDG data/config/cache roots and a 90-second timeout.

```sh
sandbox=$(mktemp -d /tmp/godot-ui-feedback.XXXXXX)
XDG_DATA_HOME="$sandbox/data" XDG_CONFIG_HOME="$sandbox/config" \
  XDG_CACHE_HOME="$sandbox/cache" timeout 90 godot --headless --path . \
  --script res://tests/canonical_ui_feedback_recovery_test.gd
```

The new test loads the actual main scene and invokes the actual connected panel handlers/signals. It inspects actual HUD footer text, model snapshot bytes (including revision), save bytes, and successful-save count. Its guarded temporary storage refuses an existing save.

Results:

- `canonical_ui_feedback_recovery_test.gd`: 19 checks, zero failures. Covers failed bind followed by success/no-change; failed inventory move followed by success/no-change; discard invalidation while the item remains visible; synchronous confirmation during cancellation feedback; late confirmation; stale-request model defense; explicit Cancel; hide; failed discard byte identity; fresh successful discard and footer recovery.
- `inventory_page_selection_test.gd`: 34 checks, zero failures. Existing visible-selection and page lifecycle regressions preserved.

- Additional `owned_gem_picker_test.gd` simulated-input run did not pass in headless mode: its first empty-slot click did not open the picker, before these changed request-feedback paths ran. Subsequent empty-choice errors stopped the test coroutine; the process was bounded by a 90-second timeout. This run is not evidence of picker acceptance, nor is the failure attributed to an established cause. No graphical runner was available for this extra check.

These are headless behavior assertions, not screenshot, pixel layout, desktop mouse, Windows, or full-suite validation.

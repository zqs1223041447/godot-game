# Scene test fixture recovery — 2026-10-15

## Scope

Test-only recovery of `canonical_group_cast_test.gd` and `skill_support_ui_test.gd`. No production code, save schema, compiler rules, or world rules changed. Runs use Godot 4.6.3 headless and fresh isolated XDG data/config/cache roots. No editor import was run.

## Reproduced baseline

- Group cast: bounded 12-second run exited **124**. The scene now correctly starts in town, where casting is rejected. The old fixture continued after four failed assertions and indexed an empty projectile array, aborting its coroutine before `quit()`.
- Support UI: bounded 15-second run exited **0**, claiming **349 checks / 0 failures**, despite script errors. Injecting obsolete `BuildState` into current Main caused missing normal-journey/reward/trade APIs and downstream world-context errors. The legacy talents path also passed two arguments to the old one-argument `PassivePanel.setup` method. This was not valid current-scene acceptance evidence.

## Repairs and coverage

### Canonical group casting

The fixture keeps Main's canonical state, uses Main's actual save path, and enters an Old Garden tier-I map through `craft_normal_map` and `start_map`. It does not force a private world-mode flag. Controlled removal of resident enemies isolates admission/resource/cooldown checks; this is not natural-combat footage or map-completion coverage.

All original substantive assertions remain: five linked supports, five actual projectiles, mana/cooldown/velocity/chill agreement, repeated-click rejection, main-gem and group cooldown identity, independent same-name gem, elapsed debt expiry, no debt on mana/capacity rejection, restored-capacity admission, binding preservation, death clearing, and restart clearing. Capacity uses the production `MAX_PROJECTILES` constant. Missing owned gems, invalid recipes, failed map entry, and missing projectiles fail before dependent indexing. A 30-second watchdog converts an aborted coroutine into nonzero termination.

### Support component and current scene

The obsolete virtual two-support component is tested directly with its actual `BuildState`, outside Main. Preserved legacy-only contracts include attach/duplicate/full rejection, physical inventory non-consumption, stale-remove identity, skill-owned support links across slot swaps, component reopening, persistence, the original 1.56 mana multiplier and volley previews, incompatibility reasons and disabled-click rejection, deliberately corrupted compiler input, visible-child clipping, and maximum-font refresh. Persistence here is an explicit test signal connection saving `legacy-support.json`; it is **not** claimed to be current Main autosave.

Current Main uses a canonical-model subclass whose only override is an explicitly toggled compiler-failure probe. Until that final probe, the production compiler runs unchanged. Current-scene checks cover:

- Formal town startup and real tier-I map entry
- A positive control showing elapsed combat time advances with panels closed, then no advance with the skills dock open
- The actual canonical physical-gem editor, five stable hotbar buttons, compiler-derived mana/cooldown tooltips, fractional-mana rejection, and exact-mana readiness
- Reused editor identity and build preservation on reopening
- A real cast establishing cooldown, followed by the editor's actual row move/return input signals attaching and removing an owned physical support; both preserve the exact cooldown ledger
- Reloading the real scene save confirms the attached support persisted
- Compiler-output fault injection makes the current hotbar disabled and visibly invalid; the injected failure is then removed
- All seven current panel types retain pause, width/viewport bounds at maximum UI/font settings, and canonical build preservation

Legacy `SelectSkill_*` and `SlotButton*` library actions and the legacy two-slot panel's placement inside Main are retired-path assertions, not current product behavior. Equivalent current physical-gem editor input and hotbar behavior are tested instead. Legacy child clipping is measured on the standalone 1200-pixel component; current dock bounds are checked separately. This test does not claim a full canonical drag-and-drop hit-target or screenshot acceptance run. Legacy talents Main integration is not repaired or represented as supported.

A 45-second watchdog and explicit missing-control/item checks prevent the old silent success/hang pattern. Acceptance requires both process exit zero **and** clean logs, because Godot can otherwise exit zero after a nested callback script error.

## Reproduction command

Run each test separately with a fresh root:

```sh
root=$(mktemp -d /tmp/godot-m1-scene-check-XXXX)
XDG_DATA_HOME="$root" XDG_CONFIG_HOME="$root/config" XDG_CACHE_HOME="$root/cache" \
  timeout 90 godot --headless --path . --script tests/canonical_group_cast_test.gd
# Repeat with a new root and tests/skill_support_ui_test.gd.
```

## Final verification

- `canonical_group_cast_test.gd`: **35 checks, 0 failures**, exit **0**
- `skill_support_ui_test.gd`: **368 checks, 0 failures**, exit **0**
- Neither final log contains `SCRIPT ERROR`, `ERROR:`, or `WARNING:`
- `git diff --check` passes for the changed tests and this document

The recovered check count is not compared as a coverage percentage: obsolete Main integration was separated from legacy unit coverage and current canonical integration was added explicitly.

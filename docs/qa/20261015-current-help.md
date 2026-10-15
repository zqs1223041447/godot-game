# Current pause Help contract — 2026-10-15

## Scope and source audit

Base: `d606de670772c38a373ffd86fec389187f372983`. Changes are limited to the existing pause controls/build cards and footer in `scripts/game_hud.gd`, one regression script, and this note. No gameplay, balance, persistence, window structure, or input routing changes.

- `CanonicalGameState.active_group_capacity()` returns 10 plus `additional_skill_slots`. Help reads that method rather than assuming five skills. A legacy Help adapter without the method receives generic “主动技能行” text, without an invented capacity.
- `canonical_build_migration.gd` binds populated initial rows with `KEY_1 + index`; it does not establish a universal five-key limit. `main.gd::_unhandled_key_input` dispatches `group_for_key`, and the canonical skill UI can change bindings. Help therefore describes each row's binding and K for rebinding, rather than advertising fixed 1–5 keys. Alt+1–5 uses flask slots.
- `KillRewardPolicy.plan` retains a random jewel every 20 eligible root kills in the current run, and a special jewel on eligible original bosses. Help keeps these rules, adds “本轮”, and says “可获得” rather than promising successful delivery. These are separate from persistent formal journey gem/flask milestones; no milestone rules were changed.
- The canonical save contains build and formal journey progress. Help no longer claims only builds persist. Restart resets the current fight; formal map retry follows the existing admission-fee transaction, including zero-cost tiers. The warning is explicitly scoped to formal maps.

## Verification

Godot `4.6.3.stable.official.7d41c59c4`, Linux headless. Run each suite with fresh isolated storage; do not use a player's save directory:

```sh
base=$(mktemp -d /tmp/godot-current-help-XXXX)
mkdir -p "$base/cache"
XDG_DATA_HOME="$base/data" XDG_CONFIG_HOME="$base/config" \
XDG_CACHE_HOME="$base/cache" godot --headless --path . \
  --script tests/current_help_contract_test.gd
```

- `current_help_contract_test.gd`: **165 checks, 0 failures**, exit 0, no script errors
- `safe_exit_hud_test.gd`: **7 checks, 0 failures**, exit 0
- `git diff --check`: clean

The new test opens the real pause panel in formal town, arena practice, and the separate test-save profile. It rebinds a real canonical row to F1, generates/equips a real catalog extra-row item to raise capacity from 10 to 11, and verifies the displayed capacity follows it. It tests the legacy Help-state fallback without substituting a legacy state for Main's canonical world API.

For each canonical scenario it checks 1280×720 and 2560×1440, font scales 1.0 and 1.2 (UI scale 1.1 for the latter), modal/footer logical viewport containment, card width, and absence of horizontal scroll overflow. Opening, closing, and resizing Help leaves canonical snapshots/revisions, both save files' bytes, world revision, and run revision unchanged. The test deliberately changes settings only to exercise presentation.

These are **headless logical-layout checks**, not native-rendered screenshot or pixel-level visual acceptance. No native visual result is claimed.

## Existing legacy encounter-suite limitation

`encounter_ui_integration_test.gd` reports **64 checks, 3 failures** both with this patch and with the original HEAD HUD in a separate temporary project using the same scripts/assets/data and fresh storage:

1. Confirm starts exactly one selected run
2. Navigating away cancels the pending request
3. Ordinary retry keeps active run selection

Both runs also report legacy fixture/Main API mismatches (`normal_journey`, `normal_pending_rewards`, `invalidate_gem_trade_quotes`, and consequent dictionary accesses). All of that suite's layout checks pass. This is a baseline-reproduced legacy integration limitation, not a passing suite; no encounter-flow repair is included in this copy-only change.

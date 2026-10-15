# Test fixture recovery independent review

Base: 11639af, branch dot/20261015-test-fixture-recovery. Review of working-tree changes; source still being finalized as of 2026-10-15 13:09 UTC.

## Confirmed
- canonical_group_cast preserves all prior substantive assertions. Uses Main's connected canonical model, supported formal-map admission, actual current capacity constant, and explicit nonzero failure on missing support/projectile prerequisites. No production edits or mock acceptance. Independent run: 34 checks, 0 failures, exit 0.
- owned_gem_picker preserves all prior behavioral assertions. Root is explicitly 1280x720; embedded subwindows apply only to headless. Mouse clicks/right-clicks, popup Enter, Escape, and V cast still use Input.parse_input_event. Existing direct id_pressed emissions are negative stale/repeated/closed checks; original direct drag/drop validation remains unchanged. Version comparison expresses action invariance rather than frozen schema 59. New prerequisite guards produce a recorded failure/nonzero exit. Independent run: 39 checks, 0 failures, exit 0.
- Legacy SkillSupportPanel is instantiated separately with BuildState and its own persistence path. Current Main is unmodified and retains CanonicalGameState. This separation accurately avoids passing an obsolete model into current production Main.
- No edits to repository, import operations, or staging performed by this reviewer. Runtime runs used fresh permitted /tmp XDG roots and timeout 90.

## Review findings being addressed
1. Current simulation-freeze check originally executed in town. Main._tick returns before elapsed advances in town (scripts/main.gd:648-652), so unchanged elapsed cannot prove pause. Requested supported formal map entry and closed-panel positive control.
2. Initial split removed historical hotbar affordability/tooltip, cooldown-preservation, stable buttons, child clipping/font refresh, modal reuse, and invalid-hotbar tests. Historical component behavior must be distinguished from current production coverage. Worker restored child clipping/font checks and current canonical affordability/stable buttons/reopen checks; adding support-edit cooldown and pause equivalents.

Initial support test passed 126/0, exit 0 before restoration; this is not final acceptance. Final revision and independent rerun pending.

Logs: /tmp/test-fixture-review-logs/{canonical_group_cast,skill_support_ui,owned_gem_picker}.log; picker JSON: /tmp/test-fixture-review-logs/owned.json.

## Final verdict — 2026-10-15 13:11 UTC

PASS for reviewed test-code scope. No remaining blocking findings. Earlier findings above were resolved before acceptance.

Final independent runs (Godot 4.6.3 stable, headless, fresh isolated XDG per test, timeout 90):
- canonical_group_cast: 35 checks, 0 failures, exit 0 (final log canonical_group_cast_final.log)
- skill_support_ui: 368 checks, 0 failures, exit 0 (final log skill_support_ui_final.log)
- owned_gem_picker: 39 checks, 0 failures, exit 0 (owned_gem_picker.log; source unchanged since run)
- git diff --check: exit 0

Review fixes verified:
- skill_support_ui:70–81 enters formal map, proves closed-panel elapsed progression, then asserts modal freeze. This removes the town-only vacuity.
- skill_support_ui:211–235 restores canonical hotbar stable names, fractional/exact mana boundaries, compiler cost/cooldown tooltips, panel identity and unchanged canonical state across reopen.
- skill_support_ui:238–263 establishes real cast debt, exercises canonical row move/return signal routes, checks persistence, and verifies exact cooldown snapshot across support add/remove/reopen.
- skill_support_ui:265–274 explicitly injects compiler failure through a small canonical subclass and checks production HUD fails closed. Cache invalidation is test setup for this controlled error, not a success stub. Normal calls delegate unchanged to the production compiler.
- Legacy component clipping and font-refresh checks are restored at lines 51–57 and 304–309.

Coverage boundaries:
Historical BuildState virtual two-slot support editing is now tested as a standalone legacy component with its own explicit persistence callback/file. The obsolete current-Main legacy slot/library coupling is intentionally not claimed. Current integration is checked separately with canonical physical gems, current panels/docks, current bound hotbar, and actual formal-map simulation. Direct row signals test editor/controller transaction integration, while picker test separately retains actual headless mouse/keyboard routing. Native OS popup/rendered acceptance and full repository-suite acceptance are not established by these headless runs. No production behavior defect was found in this reviewed scope.

Reviewed SHA-256 values:
- canonical_group_cast_test.gd: fd8d1b7cf2cd68fbfac2af0cfb58ef755173fb2d07688160ab897524e3066cbd
- skill_support_ui_test.gd: 1ad00501a74dd4a515aa21040bdacb597b411c3be9e7728fa21d07f464267b93
- owned_gem_picker_test.gd: 19145e7ad77a015cdf84f6b17a162f69cdfe967cd2b4a09f0a462ff2a9baea66

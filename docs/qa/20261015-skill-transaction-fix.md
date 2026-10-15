# Skill transaction atomicity and binding idempotence

Date: 2026-10-15 UTC. Base: `000ef21`. Godot 4.6.3 headless.

## Changes

- `slot_skill` plans movement through the existing paged transfer validator, adds the default binding to the same candidate, and persists once through the existing validated commit path. There is no intermediate persisted movement without its binding.
- If the selected gem already occupies the target but the default key is absent, the binding alone is repaired in one commit.
- Existing key mappings still choose their currently bound group. The legacy bool API remains true for a committed change and false for rejection or a completely unchanged request.
- `bind_group` recognizes an identical mapping before removing/appending bindings. Repeats preserve array order, revision, memory/disk bytes, save count and signals at every position. Changed mappings still replace competing group/key mappings normally.
- Shared candidate binding helper prevents the compound operation and explicit UI binding command from drifting.

## Targeted regression

`tests/skill_transaction_atomicity_test.gd`: 108 checks.

Before source changes: 50 failed checks, demonstrating partial compound persistence, missing binding repair and order-dependent idempotence defects.

After changes: 108 checks, zero failures, process exit 0, no script errors.

Coverage:

- Failure of the single write for move+bind and same-location repair preserves exact serialized in-memory snapshot, exact disk bytes, revision, successful saves and changed signals; independent reload matches.
- A fault armed for a second write is never reached on successful compound commands: exactly one attempted/successful save, one revision and one signal.
- Default binding creation, already-bound move and an explicitly rebound key all preserve intended group semantics and item UIDs/payloads.
- Repeated slot requests preserve the existing false/no-op bool contract and do not write.
- Every initial binding position is repeated twice; `no_change` leaves all bytes/order/counters/signals unchanged.
- Stale revision and invalid key guards remain active; ordinary explicit rebind still works.

Execution: each process uses fresh `/tmp/godot-m1-*` XDG data/config/cache, `timeout 90 godot --headless --path . --script tests/skill_transaction_atomicity_test.gd`. No editor/import run. Temporary logs: `/tmp/skill-transaction-before.log`, `/tmp/skill-transaction-after.log`.

## Compatibility checks and limits

- `canonical_game_state_test.gd`: 27 checks, zero failures, exit 0, clean log.
- `canonical_hud_integration_test.gd`: 2430 checks, zero failures, exit 0, clean log.
- `canonical_build_store_test.gd`: 40 checks, zero failures, exit 0, clean log.
- Additional historical combat/UI harness attempts are not counted as clean acceptance: `canonical_group_cast_test.gd` expects combat in its fresh town scene, fails cast assertions and accesses an empty projectile array; `skill_support_ui_test.gd` reports 349 checks/zero failures and exit 0 but emits missing normal-journey methods on its legacy BuildState fixture. The group-cast process terminates at its 90-second timeout (exit 124). Neither fixture is modified by this focused fix.
- Two `skill_binding_keys_test.gd` launch attempts exited 78 at their isolation guard; they do not count as executed test coverage. Correctly configured keybinding acceptance is delegated to the independent QA pass.
- Normal K-menu operations remain separate explicit movement/binding commands. No claim that ordinary K-menu movement routes through legacy `slot_skill`.
- Full reachable F6 behavior is covered by the separate main-scene fix and its own regressions. This document does not claim full-example atomicity or visual/pixel acceptance.

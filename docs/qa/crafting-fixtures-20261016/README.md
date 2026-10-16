# Current crafting fixture contracts — 2026-10-16

## Scope

Only three existing regression scripts change. Production code, historical schema/migration constants, frozen jewel generation fixtures, the transaction runner, and recovery-currency regression tests are outside this fixture refresh.

Checkout HEAD when verified: `07d3fa1baff402e672210be2c11647180d6c8550`.
The working tree also contains the separately owned recovery-currency production fix; focused after-runs exercise that working tree. These are local focused checks, not full-suite, editor-import, Windows or remote-delivery acceptance.

## Changes and retained coverage

- `jewel_crafting_test.gd`: replace the obsolete ten-operation count with exact ordered operation IDs from `GearCraft.operation_ids()`. This tests the model's projection against the rule catalog and catches omissions, duplicates and reordering. Frozen ordinary-jewel definitions/RNG results and the three existing equipment transaction/seed controls remain unchanged.
- `crafting_growth_transactions_test.gd`: replace a hardcoded schema 18 expectation for freshly created current models with both unchanged before/after schema and `Rules.VERSION`. All four growth operations still assert exact UID, crafting revision, currency debit, atomic failure/retry and full save roundtrip behavior.
- `normal_gem_trade_transactions_test.gd`: replace both fixed 26-definition expectations with the authoritative `Gems.definitions()` size; require a nonempty catalog. Existing per-offer unique-ID/definition metadata checks and purchases/recycling of every definition remain. Roundtrip wording now describes current schema without changing that assertion.

No assertion is deleted. The total remains 1,991 checks across the three scripts; these are checks, not independent gameplay scenarios.

## Evidence

`*.before.log` preserves the recovery worker's unchanged-fixture baseline logs from `/tmp/godot-m1-recovery-controls-pnf31png/<test>/run.log`. Before editing, these were read and the precise expected failures confirmed. That worker also verified the same failures with its production fix; the original and fixed-source logs were identical.

| Script | Before checks / failures | After checks / failures |
| --- | ---: | ---: |
| jewel_crafting_test | 1375 / 1 | 1375 / 0 |
| crafting_growth_transactions_test | 286 / 4 | 286 / 0 |
| normal_gem_trade_transactions_test | 330 / 2 | 330 / 0 |

`*.after.log` contains complete stdout/stderr for each new focused run. `runs.json` records the exact command, unique fresh XDG data directory and exit status. Each invocation uses headless Godot 4.6.3 and a 90-second timeout, sequentially during an agreed exclusive Godot window. No editor import or full suite is invoked.

After-runs emit nonfatal Fontconfig “No writable cache directories” diagnostics in this container. They are retained rather than hidden; test success is based on exit status, exact assertion summary and absence of Godot/GDScript errors, not simply process termination.

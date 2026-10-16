# Recovery queue after currency/item consumption — 2026-10-16

## Result and scope

Local production fix and targeted acceptance only. No remote writes, commits, runner edits, editor import, full-suite claim, Windows export or visual acceptance in this task.

A valid recovery location may have index `N - 1`, where `N` is total item count. Jewel salvage that credits an existing currency stack removes one item; exact currency debits remove one or more empty stacks. The previous helper left recovery indices unchanged, so the full candidate failed validation after item count shrank. The original diagnostic confirms both legal jewel quotes failed with `invalid_candidate` and `recovery index 必须小于物品总数` (18 checks, zero diagnostic failures).

The only production change is to call the existing `Transfer.compact_recovery` on the candidate locations at the successful end of `_set_bag_currency_balance`. This preserves queue UID, payload and relative order, making indices dense and bounded before caller validation/commit. No schema, prices, random seed rules, item identities, or quote lifecycle change. Failed transactions retain the original sparse queue in live memory and on disk.

## Focused red/green

`tests/recovery_currency_compaction_test.gd` extends existing fixture utilities, but overrides `run`; it does not execute the inherited legacy assertions.

- Final test on production without these three added lines: exit 1, 95 reached checks, 9 intended assertion failures
- Exact same final test with fix: exit 0, 308 checks, zero failures
- Red reaches fewer checks because unsuccessful craft/recycle gates stop their success-only assertions
- Both runs use Godot 4.6.3, fresh isolated XDG directories and `timeout 90`; no script/parse/runtime errors in accepted evidence

Cases:

1. Ordinary jewel salvage with existing shard stacks
2. Ordinary jewel reforge, exactly one exhausted stack
3. Ordinary jewel reforge, exactly two exhausted stacks
4. Equipment recalibration with exhausted stacks and unrelated recovery items
5. Normal gem recycle with existing shard stack
6. Paid-map entry still rejects pending recovery before attempting debit

Three formally admitted unrelated items are placed at valid sparse high recovery indices in reverse UID/insertion order; canonical validation and real persistence are required before every operation. Assertions verify quote nonmutation, exact `save_failed` on injected byte-write failure, byte-identical rollback, retry, canonical saved roundtrip, recovery UID/order/payload preservation, unchanged unrelated non-recovery items/positions, exact debit/credit, consumed item count, one successful save, single revisions, unchanged schema/serial, and repeated-confirmation inertness. Crafting retries reuse the existing handle; gem trade retains its established single-use-handle semantics and retries with a fresh quote.

## Shared-helper audit

All call sites were read:

- Equipment purchase (`scripts/items/equipment_purchase.gd`, `_plan`): `_guard` rejects pending items before the shared helper, so recovery is unreachable in the purchase path
- Town currency supply: existing pending-items guard prevents a recovery queue from reaching the helper
- Equipment crafting: salvage already compacted after item removal, but other operations could delete shard stacks afterward; successful helper normalization covers them
- Jewel quote preflight and execution: caller may remove the selected item before helper; quote uses an isolated trial, execution an isolated candidate
- Normal gem buy/recycle: helper normalizes before new-gem placement and full-candidate validation; recycle removes the selected gem before helper
- Normal map start: pending-items guard runs before helper, so high-recovery paid entry is not reachable; existing normal journey test exercises actual paid entries without recovery
- Normal reward claim: pending-items guard runs before helper; credits do not reduce item count

Intermediate placement was checked: debit path does not call location validation while removing stacks. Credit placement on crafting/recycle can reuse the supplied released bag cell; a new currency item restores item count before success. Existing gear salvage has its earlier compaction. Gem purchase places its new item only after helper returns. Final compaction therefore runs before the affected callers' canonical validators without weakening admission checks or mutating the live state.

## Existing regressions and explicit limits

Four existing focused suites were run against the fix:

| Suite | Checks | Failures | Result |
| --- | ---: | ---: | --- |
| normal_journey_transactions_test | 40 | 0 | Pass, includes paid admission and rollback |
| jewel_crafting_test | 1375 | 1 | Existing hardcoded ten-operation assertion |
| crafting_growth_transactions_test | 286 | 4 | Existing hardcoded schema 18 assertion, once per operation |
| normal_gem_trade_transactions_test | 330 | 2 | Existing hardcoded 26-definition/purchase counts |

The three failing suites were also run on an isolated production-without-fix copy. Their failures and counts match; they are not reported as passes and are not modified in this task. The current change does not resolve those fixture contracts. These runs are targeted compatibility evidence, not full-suite acceptance.

One initial incomplete negative-copy attempt omitted data and imported assets and produced missing-resource/script errors. It is excluded from acceptance. The accepted negative and baseline-control copy includes scripts, tests, data, assets, project.godot and existing .godot caches, with no editor import. An early test iteration also tried to reuse a normal save across distinct fresh model owners and assumed reusable gem handles; those fixture issues were corrected before final red/green. Neither failed development attempt is represented as passing evidence.

## Reproduction and identities

From repository root, use a new `/tmp/godot-m1-…` directory for each process:

```sh
XDG_DATA_HOME="$tmp/data" XDG_CONFIG_HOME="$tmp/config" XDG_CACHE_HOME="$tmp/cache" \
  timeout 90 godot --headless --path . --script tests/recovery_currency_compaction_test.gd
```

For negative controls, use an isolated complete copy and remove only the added three-line success normalization. Do not edit the shared working source while another test or review is using it.

Final SHA-256:

- `scripts/canonical_game_state.gd`: `26eda1cc6b1b98b841f9555836de0fcb3f983abd43f20c015ed0b79b5094bef7`
- `tests/recovery_currency_compaction_test.gd`: `7f61475989b00358fd6f6bcca92edb6cc8546fa756beba9a8b4926f92f9cd198`

Logs in this directory are compact process output. Final green source: `/tmp/godot-m1-recovery-final-qnvL/run.log`; negative/baseline controls: `/tmp/godot-m1-recovery-controls-pnf31png/`; existing after suites: `/tmp/godot-m1-recovery-regressions-fx0rs368/`. Temporary game saves are not deliverables. Independent review is reported separately by the parent.

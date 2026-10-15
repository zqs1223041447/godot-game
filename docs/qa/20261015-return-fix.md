# Return transaction and F6 partial-failure regression

Date: 2026-10-15 UTC. Base: `000ef21`. Godot 4.6.3 headless, existing imported resources, no editor/import process.

## Changes

- `Main.return_to_town` flushes ordinary progress **before** completion/abandonment. Abandonment is the last fallible operation before the synchronous town transition. A failure of either write therefore leaves a playable unfinished map with its valid canonical completion identity. Previously abandonment succeeded first, then a failed plain save left a playable map whose completion could never settle.
- Successful completion remains a separate canonical transaction. Its reward receipt and best tier are preserved; successful returns still perform one ordinary save and one abandonment when the run is unfinished.
- F6's example action checks already-satisfied skill/key and equipment postconditions, stops at the first failed mutation, and reports incomplete setup with retry guidance. Earlier successful equipment operations remain persisted and are disclosed in feedback. It only announces the full combination after all requested steps succeed. Retrying a complete build makes no writes and still reports success.
- F6 relies on the accompanying canonical `slot_skill` atomic move-and-binding fix. Bound and unbound setup each now have four persistence boundaries: skill/binding, bow, mantle, charm.

## Before/after evidence

1. The new `return_transaction_failure_test.gd` ran against the old Main with `RETURN_FIXTURE=free RETURN_CASE=second_clear`: 22 assertions, **7 failures**. Failures included missing active run, missing completion receipt/tier, and inability to return after clear. The same case after the ordering fix: **22/22 passed**.
2. The old F6 function was replayed verbatim via a temporary Main subclass with the new canonical model, using the new F6 harness, unbound fixture, failure at write 2: **4 failures** (continued writes, false success, false key claim, false explosion claim). The production fixed function: **17/17 passed**. This isolates Main feedback behavior; it is not a claim that the original canonical model was unchanged in this comparison.

## Completed validation

| Suite | Cases | Assertions | Failures |
| --- | ---: | ---: | ---: |
| Return transaction matrix | 18 | 387 | 0 |
| F6 failure/retry matrix | 10 | 163 | 0 |
| Existing `safe_map_exit_test.gd` | 1 suite | 120 | 0 |

Return fixtures are free old_garden tier I, paid old_garden tier II, and tier II with `enemy_max_health_120`, `enemy_shield_from_health_20`, `elemental_aegis`. Paid unlock and four shards are established using supported start/complete/claim transactions; no journey or currency field is overwritten. Each fixture exercises:

- First-write failure, then full clear
- Second-write failure, then full clear
- Second-write failure, immediate return retry
- Second-write failure, one combat kill, return retry
- Second-write failure, fresh scene reload (ordinary unfinished-run abandonment)
- No-fault clear control

Checks cover live/disk agreement after failure, continued completion identity, correct 4/8/12-shard receipt and original run ID, correct tier advancement, no duplicate debit/refund, duplicate-return rejection without mutation, exact canonical snapshot after fresh scene reload, and successful/idempotent safe exit. A safe-exit spy replaces only process termination. Full clears use production damage/completion methods in deterministic batches, not UI mouse playthrough.

F6 exercises the actual visible connected `EquipTornadoExample` button signal, both initially bound and unbound fixtures, every actual write boundary, and controls. Checks cover stop-on-failure, truthful incomplete feedback, disk equality, complete component/effect/key postconditions after retry, and no-write idempotence. The skill failure is asserted fully unchanged.

Every process used its own fresh `/tmp` XDG data/config/cache with `timeout 90`. New suites refuse an existing save or a non-`/tmp` XDG data directory. One initial invocation of the existing safe-exit suite exited 78 because its stricter directory-prefix guard rejected the fixture; it was rerun under its required prefix and passed. No timed-out/aborted process is counted as passing. No Windows, rendering, FPS, manual-input, or all-map/all-affix claim is made.

## Reproduce

From the project root, run each combination in a fresh directory:

```sh
for fixture in free paid affixed; do
  for mode in first_clear second_clear second_retry second_kill second_reload control; do
    base=$(mktemp -d /tmp/return-fix.XXXXXX)
    RETURN_FIXTURE="$fixture" RETURN_CASE="$mode" \
      XDG_DATA_HOME="$base/data" XDG_CONFIG_HOME="$base/config" XDG_CACHE_HOME="$base/cache" \
      timeout 90 godot --headless --path . --script tests/return_transaction_failure_test.gd || exit $?
  done
done
for unbound in 0 1; do
  for fault in 0 1 2 3 4; do
    base=$(mktemp -d /tmp/tornado-fix.XXXXXX)
    TORNADO_UNBOUND="$unbound" TORNADO_FAIL="$fault" \
      XDG_DATA_HOME="$base/data" XDG_CONFIG_HOME="$base/config" XDG_CACHE_HOME="$base/cache" \
      timeout 90 godot --headless --path . --script tests/tornado_example_failure_test.gd || exit $?
  done
done
base=$(mktemp -d /tmp/godot-m1-v099-return.XXXXXX)
XDG_DATA_HOME="$base/data" XDG_CONFIG_HOME="$base/config" XDG_CACHE_HOME="$base/cache" \
  timeout 90 godot --headless --path . --script tests/safe_map_exit_test.gd
```

With no case variables, the new return suite defaults to free/second_clear; F6 defaults to bound/control. The root integration owns commits, remote delivery, and merge verification.

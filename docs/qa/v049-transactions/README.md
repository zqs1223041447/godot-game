# v0.49 targeted-reforge transaction validation

Validated on 2026-10-05 with Godot 4.6.3, after the shared project import completed. The focused headless suite reports **943 checks, 0 failures**, exit 0. See [transactions.log.txt](transactions.log.txt).

Run from the project root:

```sh
XDG_DATA_HOME=$(mktemp -d /tmp/godot-m1-v049-transactions-data-XXXXXX) \
XDG_CONFIG_HOME=$(mktemp -d /tmp/godot-m1-v049-transactions-config-XXXXXX) \
XDG_CACHE_HOME=$(mktemp -d /tmp/godot-m1-v049-transactions-cache-XXXXXX) \
/usr/local/bin/godot --headless --path . \
  --script tests/targeted_crafting_transactions_test.gd
```

The test refuses to run without its `/tmp/godot-m1-` data-home isolation. It instantiates canonical models directly and does not launch the gameplay scene or the GUI. No historical full suite or broad 600-second wrapper was run.

## Verified behavior

- All four target operations execute as real canonical transactions for magic and rare items, charging exactly 16 and 40 actual calibration shards. Dynamic source and shard UIDs use the current canonical serial, avoiding obsolete hardcoded fixtures.
- Successful quotes retain the exact established envelope plus `handle`; the selected target is encoded by `operation`, without an extra target field, rolled output, seed, or candidate.
- Metadata retains the old six operation shapes, adds exactly `targeted`, `target_id`, and `target_label` to the new four, reflects target eligibility and funds, and does not allocate handles, write, mutate memory, or advance global RNG. Returned economics are detached.
- Cancellation, duplicate confirmation, mismatched source, submitting a quote dictionary as a handle, insufficient funds, unknown targets, wrong rarity, ineligible bases, stale model revisions, and pre-reload handles all reject without changing canonical state or save bytes.
- Tampering with the detached visible quote's operation, source, cost, or additional target field cannot change the operation or price bound to the model's stored handle. Planner tests separately reject altered envelopes, invalid operations, altered prices, source/rules/revision changes, and protected saves without input mutation or global RNG use.
- An injected write failure preserves the entire previous snapshot and raw save bytes, produces one failed write attempt and no successful-save count or change notification, and retains authority for one successful deterministic retry. The retry makes one successful save and one notification.
- The exact complete post-craft build differs only in the crafted payload, paid shard records/locations, and the model/crafting revision increments. Gear UID, base, level, rarity, bag page/cells, all unrelated inventory UIDs, next serial, journey and schema30 remain unchanged.
- Outputs contain an existing family from the independently listed selected target, satisfy catalog group/base/tier/value/rarity limits, match the authoritative deterministic plan, and roundtrip through a full schema30 save.
- Raw external file re-encoding is detected even when it represents the same JSON object; its bytes are preserved and metadata reflects save protection.
- A real targeted life-leech craft spends across two shard UIDs, removes the exhausted stack, and retains the partially spent stack's UID and location with exactly seven shards. The crafted ring equips through `move_item` into `ring_1`; the final `get_basic_cast()` consumes its exact life-leech basis-point fraction, including after a full reload. Compilation causes no additional save.

## Scope and fixture correction

The planner is stateless; editing one valid same-price target operation into another can describe a different valid quote. Provenance is enforced by the model's opaque stored handle. The suite tests that boundary rather than inventing a target field or signature in the planner envelope.

The first run had four test-expectation failures because a zero-wallet post-craft planner projection reaches the insufficient-funds guard before stale-revision validation. The corrected test checks that rejection and then re-funds a detached projection to isolate the stale-revision check. No production change was needed. The initial output is retained in [initial-fixture-correction.log.txt](initial-fixture-correction.log.txt).

This focused suite does not replace the separate pure-rule distribution/economy proofs, interactive UI evidence, or exported-PCK validation.

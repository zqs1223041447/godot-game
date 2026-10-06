# v0.83 fourth-map save and Normal transactions

This focused collection covers the affected migration and real Normal-model boundaries. It does not claim a rerun of every historical suite.

- Production envelope: schema50, source talent execution policy49, equipment vocabulary46
- Genuine source fixture: `docs/qa/v082-source/fixtures/witch-refunded.json` (released native49, unchanged equipment and source data)
- New migration changes only `version: 49 → 50` and adds `journey.best_tiers.ginkgo_arcade: 0`
- Frozen journeys: schema26–29 uses two map keys; schema30–49 uses three; schema50 requires exactly four
- Old49 fourth-map key, run, or pending-reward injection fails full native validation before any backup or write
- Migration validates all existing fields, retains original serialized bytes in the original-version backup, and publishes memory only after the atomic save succeeds

## Focused executable collection

`tests/fourth_map_journey_test.gd` requires an isolated `XDG_DATA_HOME` beginning with `/tmp/godot-m1-v083-save-`. Run it only after the project owner's coordinated editor import.

The collection checks original three-map active and pending states, old affixed profiles, strict current and frozen key sets, full25→50 loader passage, frozen48→49 endpoint, backup/atomic/concurrency failures, and actual new-map Normal start/complete/claim/retry/abandon transactions. It covers all three new tiers, exact existing fees and rewards, duplicate settlement, full inventory, owed ordinal retention, write failures, and external save protection.

## Reusable legitimate fixtures

`tests/fixtures/v083/ginkgo_journey_fixture.gd` exposes `prepare(game, path, tier=1, start_run=false)`. Use an isolated normal `user://build_save.json` path. It imports the genuine native49 fixture, migrates it, then uses real start/complete/claim model calls to unlock each requested tier. It creates no gear, shards, points or unlocks outside the existing model transactions.

The focused collection exports:

- `fixtures/v50-ginkgo-I-ready.json`: tierI open, no gifted items or currency
- `fixtures/v50-ginkgo-I-active.json`: unfinished tierI with persisted run
- `fixtures/v50-ginkgo-I-pending.json`: completed tierI, four shards owed
- `fixtures/v50-ginkgo-II-ready.json`: tierII unlocked, earned four shards available
- `fixtures/v50-ginkgo-III-ready.json`: tierIII unlocked, earned eight shards available
- `fixtures/v50-ginkgo-full-pending.json`: genuine full inventory with map and milestone rewards retained
- `fixtures/v49-<old-map>-active.json` and `-pending.json`: original three-map vocabulary with legal progress and retained claim ordinals

Verified once after the coordinated editor import: **199 checks, 0 failures**, exit0, 33.654 seconds, Godot4.6.3. No script/runtime errors were logged. There was no failed attempt and no repeated collection run.

- `save-report.json`: semantic coverage, check counts, source policy and equipment vocabulary
- `fourth_map_journey_test-attempt01.log.txt` and `-result.json`: exact first-run output, status and isolated user-data location
- `tested-input-sha256.json`: the exact tested production/test dependencies
- `fixture-provenance.json`: exported fixtures, SHA-256 values, versions, complete journey state and item counts; independently verifies that tierI-ready differs from native49 only in version and the new zero tier key

Command: `godot --headless --path <project> --script res://tests/fourth_map_journey_test.gd` with independent data/config/cache directories under `/tmp/godot-m1-v083-save-fzjn0tyx`.

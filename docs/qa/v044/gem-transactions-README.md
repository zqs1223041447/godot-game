# v44 normal gem trade transaction evidence

Final focused result on 2026-10-04: **282 checks, 0 failures**, exit 0, no Godot script or assertion errors. Godot 4.6.3 completed the test in 28.743 seconds. All seven recorded model/catalog/test input hashes were unchanged during execution.

- Test: `tests/normal_gem_trade_transactions_test.gd`
- Passing log: `gem-transactions-final.log.txt`
- Command, isolated XDG root, elapsed time, exit status and SHA-256 inputs: `gem-transactions-tested-files.json`
- Scope: this one model transaction test only; this result does not claim a complete repository or UI pass

## Exercised behavior

- Purchase and recycle every one of the 26 live gem definitions, using actual level-1/quality-0 catalog instances, active cost 8, support cost 4, and recycle credit 1
- Exact per-success debit/credit, unique UID allocation, one canonical revision, one save, one `changed` notification, canonical reload equivalence, no global RNG consumption, and unchanged schema/journey/crafting revision
- Lightweight detached offer/recycle metadata with no snapshot, disk stamp, issued handle or save; returned quote mutation cannot alter the held transaction
- Strict literal requested and opened normal save paths; unopened, test-profile and equivalent-path models cannot trade
- Malformed operations/IDs/revisions, insufficient bag currency, recovery currency exclusion, equipped main/support/equipment/flask and recovery gem exclusions
- Forged/consumed/canceled/invalidated quotes, wrong target, identical-profile reload, same-revision full-state mutation, intervening revision, profile retirement, and commit-signal reentry
- Atomic failed save and fresh-quote retry, full prepared-candidate validation, exact disk-byte conflict including same-JSON trailing whitespace before execution or new issuance
- Full-bag exact last-stack cell reuse, retained-stack rejection, split-stack debit, exact selected recycle cell reuse, existing-stack credit merge, and preservation of an unselected gem sharing the same definition
- Registry, revision, serial and global currency limits including recovery; terminal-serial recycling both with and without an existing shard stack; corrupt allocator/float currency/float gem payload/unrelated progression rejection

Fixtures begin with the real migrated canonical profile and commit to literal `user://build_save.json`. The runner verifies `/tmp/godot-m1-*` XDG isolation before touching that path. Full bags and registry-limit fixtures batch their catalog instances into one validated commit instead of asserting once per filler item.

## Retained failed runs

`gem-transactions-first.log.txt` is **invalid test evidence**: a test-subclass constructor accidentally skipped canonical initialization, causing runtime errors. Its printed “0 checks, 0 failures” is not a pass. The harness now preserves the inherited constructor and connects its observer after construction.

`gem-transactions-second.log.txt` is **failed evidence**: 236 counted checks, 3 path assertions failed, plus script errors. It exposed equivalent-path acceptance, malformed-operation comparison before type checking, and treating metadata's array footprint as a `Vector2i`. The model owner fixed those three production issues before the final run. A subsequent test review also replaced a nonexistent active-ID constant with the live `skill:bolt` definition for the recovery-funds rejection scenario.

Only `gem-transactions-final.log.txt` and its matching hash manifest establish the passing result.

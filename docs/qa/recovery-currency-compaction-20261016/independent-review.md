# Independent review: recovery currency compaction

Date: 2026-10-16 UTC
Verdict: No blocking finding in the reviewed production change and regression test. Focused green/red discrimination independently verified. Worker QA documentation and stored evidence also reviewed; claims accurately distinguish fixed regression from existing stale-fixture failures.

## Reviewed identities

Repository: /workspace/scratch/a51485f153de/godot-game
Baseline HEAD: 07d3fa1baff402e672210be2c11647180d6c8550
Branch: dot/20261015-skill-binding-focus

- scripts/canonical_game_state.gd SHA256: 26eda1cc6b1b98b841f9555836de0fcb3f983abd43f20c015ed0b79b5094bef7; Git blob a073f27c9fc03382db3acaaffe036272692d8b82
- tests/recovery_currency_compaction_test.gd SHA256: 7f61475989b00358fd6f6bcca92edb6cc8546fa756beba9a8b4926f92f9cd198; Git blob 44b2ddf4b250082dad4697dc3bd7082924fb42c9

Hashes independently checked unchanged after both test runs. No active production edits/reverts, staging, commits, or remote writes performed. Read AGENTS.md and ACTIVE_WORK before review.

## Independent execution

Evidence root: /tmp/godot-m1-review-recovery-u5X0RV
Godot: 4.6.3.stable.official.7d41c59c4
Copied project, scripts, tests, assets, data, scenes, shaders, and import cache into isolated repo. No missing-resource or parser errors occurred. Both runs used separate fresh XDG_DATA_HOME, XDG_CONFIG_HOME, XDG_CACHE_HOME directories below that temporary root, and timeout 90.

Command form: env XDG_DATA_HOME=<root>/<positive|red>-data XDG_CONFIG_HOME=<root>/<positive|red>-config XDG_CACHE_HOME=<root>/<positive|red>-cache timeout 90 godot --headless --path <root>/repo --script res://tests/recovery_currency_compaction_test.gd

- Fixed source: 308 checks, 0 failures; exit 0
- Red control: only isolated canonical_game_state.gd replaced with git show HEAD:scripts/canonical_game_state.gd; identical final test: 95 checks reached, 9 expected failures; exit 1
- Red failures: save-fault reachability and same-quote retry for salvage, single-stack jewel reforge, split-stack jewel reforge, equipment recalibration; gem recycle quote rejected before execution
- No timeout, crash, parse failure, or unrelated missing-resource failure counted as red success
- positive.log SHA256 e1949d9e8a91e6c5ed36bc90e00c746ece85270876130b2effe4d4ef5ba6c72e
- red.log SHA256 2fd111577b00ab72f63bc91ca8025d48971f998da22a03032c17ea27a34d1666

## Code and behavior review

The 3-line production change calls existing Transfer.compact_recovery at the successful currency-helper boundary. Item-count reduction can invalidate formerly legal recovery index N-1. Compaction deep-copies locations, sorts recovery by original valid unique indices, assigns 0..K-1, and leaves UIDs, payloads, non-recovery locations and queue relative order unchanged. Reversed UID/insertion order plus sparse high-index fixtures guard against accidental UID or dictionary ordering.

All helper call sites reviewed: town_claim_offer, equipment crafting, jewel quote preflight and execution, gem buy/recycle quote, normal_start_map, normal_claim_rewards, and equipment_purchase._plan. Callers use detached snapshot/trial candidates. Existing town, map, rewards and equipment-purchase pending-item guards remain. Gem buy may also safely benefit when stack removal shrinks item count; no purchase semantics changed. Existing equipment salvage compaction is redundant but safe and intentionally untouched.

_commit still validates and persists before accepting memory and emitting changed. No new save, revision increment, UID allocation, schema change or quote consumption is introduced by compaction. Failure paths discard detached candidates. Focused tests assert exact memory/disk rollback, exact save_failed reachability, same-quote crafting retry, one successful save/signal, repeated-confirmation inertness, and persisted state roundtrip. Gem trade intentionally consumes its handle before commit, requiring a fresh quote after failure; this remains explicitly tested. Paid-map unresolved-recovery guard still rejects before debit with unchanged disk/state.

The fixture accepts only isolated /tmp/godot-m1- XDG data. It deletes only its own isolated normal-profile fixture. Test early returns on failed quotes/results reduce red-run reached checks to 95; this is documented rather than claimed as 308 red assertions.

## Verification limits

Only the new focused regression was independently executed by this reviewer. No full suite, visual/Windows validation, performance benchmark, CI, remote publication or merge is claimed. Worker reported existing stale-fixture failures in jewel crafting, growth transactions and gem trade; these must remain explicit failures until baseline equivalence is verified or fixtures are corrected. Journey transactions worker result 40/0 is separate evidence, not this reviewer's independent run. git diff --check passed.

## Final evidence documentation review

Reviewed docs/qa/recovery-currency-compaction-20261016/README.md and all ten stored logs. One completeness nit (missing external equipment_purchase helper caller) was corrected before final review. Independently used cmp to verify each existing failing-suite before/after pair is byte-identical: jewel crafting 1375/1, growth transactions 286/4, gem trade 330/2. These are known baseline failures, not passes. Worker focused logs are byte-identical to independently generated green/red logs. No blocking documentation finding. Separate future fixture changes are outside this frozen review and require their own checks.

Baseline canonical source SHA256: 218cb903e4b99297d13e29e387dfcbfd55501c82f37e7dfda7a8529bbd277787

Final QA SHA256 manifest:
- README.md: aa1146093c0afd1e46eda89599a508e1fdfe18143366660fbcd4de00faee2ea1
- crafting_growth_transactions_test-after.log: d9c3fe896b1eb305e4ef9c27eab9a215cb88f32c9ffe5fd9fa9ba4385ec29028
- crafting_growth_transactions_test-before.log: d9c3fe896b1eb305e4ef9c27eab9a215cb88f32c9ffe5fd9fa9ba4385ec29028
- focused-after.log: e1949d9e8a91e6c5ed36bc90e00c746ece85270876130b2effe4d4ef5ba6c72e
- focused-before.log: 2fd111577b00ab72f63bc91ca8025d48971f998da22a03032c17ea27a34d1666
- jewel_crafting_test-after.log: a511356fc9004947e6623eef588fac8acc6dcc87173e9beae5786666c15b06c9
- jewel_crafting_test-before.log: a511356fc9004947e6623eef588fac8acc6dcc87173e9beae5786666c15b06c9
- normal_gem_trade_transactions_test-after.log: 7f171215d6525ffe9624c05ff3d53cfa821fbc3dd8d063b77e6dda71076824aa
- normal_gem_trade_transactions_test-before.log: 7f171215d6525ffe9624c05ff3d53cfa821fbc3dd8d063b77e6dda71076824aa
- normal_journey_transactions_test-after.log: 16c5951bb10946693d5649a9e0fa126b493db927e6b57070d9bf26b498f6f9bd
- original-diagnostic.log: daeeaa5f251b25dc91eba3016f59bfcd325bce65e41c7b76d284bc3ba3cef87d

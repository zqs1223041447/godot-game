# Standard reward decision boundary

2026-10-11 · Godot 4.6.3 headless · published baseline `180853467e352d84984471759366faeb633a19f5`

The independently tested local baseline `1771b238440a22288dd245c9253fca3cb3727ede`
has the same complete tree `cb77ae60f36edc8e4d457ca932181b65521b9253`.
The runner defaults to the published commit for fresh GitHub checkouts. In the
original dot checkout, where that remote commit object is absent, use
`BASELINE_REF=1771b238 tools/validate_reward_policy.sh`; no network access is needed.

## Scope

`KillRewardPolicy` is a pure decision module. For maps, it resolves the route only
from the admitted birth record and verifies the actor's source key. Only
`standard` is supported. Invalid routes/source bindings stop death settlement
before status cleanup, the once-only death ledger, descendant reservations,
map progression, reward execution, and death RNG draws. Actor route hints are
not a source of authority. Malformed non-string routes now return an explicit
failure instead of triggering GDScript's mixed-type comparison error.

After `MonsterRuntime.process_death` confirms the once-only identity, the policy
plans the original reward count, flask charging, XP profile/amount, equipment,
jewel, test gem/flask, formal milestone, boss jewel and pickup decisions.
Main executes them in the original order. Noneligible deaths return an all-disabled
plan before reading reward-only XP or rarity payloads; demo/descendant deaths still
finish their original death effects and RNG draws. Formal milestones intentionally read
the actual count **after** XP execution: a declined XP write must retain the old
behavior. Existing item-generation helpers and reward model transactions remain
the executors; the policy never rolls RNG, grants items, mutates state, or saves.

Map root progress is independent of payout. MonsterRuntime still owns death
splitting, generation/queue/lineage limits and rewardless descendants. No season
switch, essence item, new mechanism, save field, drop rate, XP rule or charge
rule has been introduced. Nonempty mechanism configuration remains rejected by
the existing admission layer. Future optional encounters can add a validated
route and its policy without mixing reward routing into descendant generation.

## Reproducible bounded equivalence

Run `tools/validate_reward_policy.sh`. Every invocation isolates data/config/cache
under temporary directories and limits each Godot process to 120 seconds. It
extracts the frozen baseline Main with `git show`, then runs the same integration
probe first against that script and then against candidate Main. Dependencies
are shared and unchanged by this patch. It compares full serialized observations,
not merely final reward totals. It leaves logs and both JSON records in the
printed evidence directory. No user saves, export, full suite or 600-second soak
are used.

The six controlled arena cases cover formal/test profiles, prior reward counts
0/58/118, normal/magic/rare/boss roots, the 8/20/30/60 boundaries, equipped flask
charges, duplicate deaths, deferred children, demo roots, write failures and
retries. A real free old-garden entry covers all 25 admitted roots, the formal
boss reward path, source-route rejection, derived deaths and actual return to
town. The fixtures are controlled reward probes, not natural gameplay evidence.

Four additional short-circuit cases pass malformed unused XP (`{}`) through
actual `_finish_enemy_death` for demo roots and real drained rewardless descendants,
on both formal and test profiles. They verify full tail-RNG execution, no payout,
unchanged character/save/flask state, and once-only processing. The pure policy
also checks that a rewardless rarity hint is never converted. These cases guard
the short-circuit regression found during independent review.

The oracle captures typed character state, gameplay RNG state, kills/reward
counts, flask runtime, lineage ledger/queue, pickups, health/mana, map progress,
world revision, save attempt/success/dirty flags, and exact disk bytes.

Results:

- Pure policy: 1,368 checks, zero failures
- Frozen Main: 139 checks, zero failures, 65 observations
- Candidate: 144 checks, zero failures, 65 observations (includes four extra
  malformed-route rejection probes and the oracle comparison)
- Both oracle files SHA-256:
  `eaa09df45fb255f7f4d9e8d0e66bf3b5e979ff0861ce9a02c77a2e2e99ff1b4d`
- Exploration map plan: 352 checks, zero failures
- Monster system: 266 checks, zero failures
- Existing exploration Main flow: baseline 291 / candidate 243 checks, both zero
  failures, four map entries each; this timing-dependent suite is supplementary,
  not the exact-equivalence oracle
- Headless editor/import and `git diff --check`: passed

## Known baseline failures, not repaired here

The focused legacy `monster_integration_test.gd` fails 18/85 checks on both the
frozen Main and candidate, with the same failure labels. Its legacy BuildState
fixture and demo/lifecycle expectations do not match the current Main contract.
`flask_gameplay_test.gd` likewise fails 10/61 on both with the same error labels;
its initial town/safe-area fixture no longer supports the expected combat use.
These failures are not counted as passing coverage. The new isolated integration
probe exercises current profile and formal-town entry contracts explicitly.

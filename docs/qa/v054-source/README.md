# v0.54 faster damaging ailments: source and save evidence

Scope: exact source-line parser, whole-node execution policy and schema32→33 persistence. Combat and UI behavior are verified separately.

## Source contract

The pinned official source remains 3.29.1, original source SHA256 `7e9f755e33152129ebf36c2ebdad639c527e4ad70d274b1fefb860f30ca01122`. The only newly recognized grammar is `Damaging Ailments deal damage X% faster`, represented by the additive fraction `damaging_ailments_faster` (5% → 0.05).

Exactly three standard nodes become full: 11364 Faster Ailments (5%), 43684 Faster Ailments (5%), and 59766 Dirty Techniques (15%). Their complete branch sums to 25%. All seven class starts have 685→688 reachable ordinary nodes; there are no additional newly reachable existing nodes.

There are two additional parsed occurrences, neither allocatable:

- Standard 48823 Deadly Draw: `Damaging Ailments deal damage 10% faster`; `30% increased Damage Over Time with Bow Skills` stays unsupported, so the node remains partial
- Nonstandard 19686 Wasting Affliction: `Damaging Ailments deal damage 5% faster`; `20% increased Damage with Ailments` stays unsupported, so it remains partial and outside the standard graph

There are zero matching mastery occurrences. Every old full node and mastery retains its exact released32 grants. Source IDs, graph topology, point budget and source version are unchanged.

## Historical fixtures

`capture_released_v53.gd` ran once against the already imported published v53 snapshot at `/workspace/scratch/a51485f153de/v053-final-source-snapshot`, parent-verified published commit `e3a5f7559ecbcb2cb56a9c192d75899fdcf43b3a`. It produced a default save, a real active journey with actual existing Fire DoT allocations, and a complete released32 full-node/mastery oracle. No current envelope was relabeled to manufacture a historical fixture.

The capture exited 0 in 2.072 seconds. `fixtures/manifest.json` records the exact command, capture script hash, released source hashes, fixture byte lengths and fixture SHA256 values. The source bytes deliberately contain leading whitespace and CRLF; migration must preserve them in the `.v32-backup.json` file.

## Focused verification

After the parent's single shared import, run `python3 docs/qa/v054-source/run-focused.py`. Each test receives unique isolated XDG data/config/cache directories beneath `/tmp/godot-m1-v054-source.*`.

First run `evidence-4vi09ue_.json`:

- `source_faster_burn_rules_test.gd`: exit 0, 6,723 checks, zero failures, 3.170 seconds
- `source_faster_burn_migration_test.gd`: exit 0, 269 checks, zero failures, 16.381 seconds

The evidence records the actual commands, exits, elapsed times and tested source hashes. Both logs are retained. There were no initial failures or retries. All recorded source hashes still matched after the tests.

Coverage includes malformed/scoped/nonfinite parser input; separate old and current caches; exact released32 whole-tree gates and grants; every class path; actual persisted allocation, refund, illegal disconnect refusal and reopen; schema14–32 new-node injection rejection using genuine historical envelopes; strict32 validation before33 migration; frozen FireDotMigration31→32 output; version-only changes and old-stat identity; raw backup collision/failure; external writes during backup and after load; real atomic-temp collisions; no visible mutation on allocation/refund failure; retries; and preservation of previously accepted memory/disk receipts.

Only the two focused current source/save suites and one small old-source capture were run. This is not a claim that every historical test suite or combat/UI suite ran.

# Independent burn state-copy candidate review

2026-10-15 UTC. Verdict: no production correctness blocker found; candidate passes its declared narrow experimental gate. This is not evidence of broadly stable performance or Windows FPS improvement.

## Source and ownership

The production diff is limited to `_plan_advance`'s outer `state.duplicate(true)` becoming `duplicate(false)` and two explanatory comments. All three callers were inspected:
- `apply` keeps the planned status privately or replaces it with a new state whose input provenance is deep-copied
- `advance_target` commits the private planned status; returned segments contain separately deep-copied provenance
- `advance_all` plans against detached `statuses()` values and commits only after every plan succeeds

The planner mutates only scalar `remaining` and `last_time` on a fresh outer dictionary. Provenance validation allows only strings, integers and finite numeric fields; no nested user containers enter the state. `status_for`, `statuses`, and segment provenance remain deep-copied. Failed reverse-clock or underflow/overflow planning does not mutate the original. Repository search found only the three intended production planner call sites. Future private provenance mutation or new planner consumers would need renewed ownership review; the comment correctly states this condition.

## Independently verified evidence

- Baseline source manifest: all 238 script hashes matched git commit `461824776e500ea868f72aea58a4f54db40b4423`
- Frozen runtime matched that baseline after removing the class name and normalizing its frozen rules import
- All 12 run records completed with exit code zero. Each record's 241 before/after source hashes matched each other and the reviewed source bytes
- All raw binary observations and save files were read from `/tmp/burn-state-copy-20261015-observations`, compared byte-for-byte, and checked against recorded SHA-256 and lengths
- Summary reports 36 checks, but nine are baseline self-checks. There are 27 non-self comparisons: 18 candidate-to-baseline and nine second-baseline-to-first comparisons
- All 240 frame timings were used to recompute each run's means/maxima. Gate was independently recomputed from per-run JSON, rather than trusting summary decisions; both ember and control conditions pass
- Gate file timestamp predates earliest completed run record, consistent with worker's predeclaration. No new timing runs were performed by reviewer

## Limits and gate outcome

Ember pooled mean ratio 0.92497795 (~7.50% improvement), pooled max ratio 0.86006138 (~13.99% improvement). Both individual pairs improved for both measures, meeting >=3% pooled improvement criteria.

Controls are noisy. No-burn mean pair ratios 0.96672 / 1.04402, pooled 1.00383. Ignite mean pair ratios 0.84433 / 1.14248, pooled 0.98671; ignite max ratios 0.90811 / 1.18202, pooled 1.04170. Thus a materially slower second ignite pair exists; pooled max regression is +4.17%, narrowly below the declared >5% rejection threshold. The declared criterion also rejects >3% regression in BOTH pairs, which neither control exhibits. Passing this limited gate must not be described as all controls improving or stable universal performance. Only two paired short 20-tick samples per mode were evaluated, with no inference about Windows/rendered FPS.

## Independent functional run

After the validation worker confirmed all Godot work complete, ran `tests/burn_state_copy_20261015_test.gd` with isolated fresh `/tmp/godot-m1-v050-independent-*` XDG data/config/cache: exit 0, 892 checks, 0 failures; no script errors. Log: `/tmp/burn-state-copy-review-test.log`. An initial attempt with a different temp prefix was refused by the test's isolation guard (exit 78, no checks); corrected to the required prefix and reran. `git diff --check` passed. No source or git changes made by reviewer.

Publication still requires the parent to check the final staged file tree and delivery; the test/artifact review does not certify an unreviewed later edit or a remote commit.

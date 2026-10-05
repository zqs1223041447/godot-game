# v0.51 empty-radius allocation comparison

Completed once on 2026-10-05 in the parent's exclusive CPU window, using Godot
4.6.3 headless. First attempt exited 0: **447 checks, 0 failures, 28 cases**.
The completion marker and clean engine output are in run.log; full typed-result
records and raw timing batches are in result.json. No failed attempt or rerun
was needed. execution.json records source/artifact hashes and the isolated roots.

The frozen fixture tests/fixtures/v051/source_tree_allocation_before.gd reproduces
v050 (7b1642d) source_tree_allocation_rules.gd with only its class_name changed to
FrozenV051Allocation. Source/fixture hashes and the byte-identical reverse-transform
check are recorded in baseline-provenance.json. The test repeats the hash check.

The focused test uses SourceTreeRuntime._context(0,123), the real pinned 2,387-node
Scion graph. It compares both fully validating public analyze and the owner's
private validated-context entry. Cases cover no jewel, an ordinary jewel, the real
6230 socket / 26740 remote-node dependency with a 280 radius, absent/broken paths,
disconnected allocation without coverage, zero/exact/just-inside/just-outside
radius, point-budget boundaries, malformed rules/types, duplicate/unknown
selection, invalid public contexts, reordered dictionaries/selection and detached
results. The square-root boundary explicitly accounts for float rounding.

Every call checks unchanged complete typed input bytes and exact result bytes
between old/new code, including array types, order and failure reasons. Global RNG
sentinels and a separate RNG state must remain unchanged. Cases record result bytes
as hex and a SHA-256 of the input typed-bytes hex. These are pure rule tests;
gameplay settlement and disk rollback need the separate production-path comparison.

Optional timing (ALLOCATION_V051_TIMING=1) prepares fixtures and validates the
context before measurement. It uses five alternating-order batches of eight
private analysis calls per implementation for no-jewel, ordinary-jewel and real
special-jewel cases. Only analysis and identical loop/dispatch overhead are timed.
Serialization, checks, public graph validation and fixture construction are excluded.
Raw batches and medians are descriptive; no timing threshold gates correctness.

## Observed private analysis CPU

Five alternating-order batches of eight calls, median per call:

| Real pinned-context case | Frozen v050 | Guarded v051 |
| --- | ---: | ---: |
| No jewel, starting allocation | 1554.375 microseconds | 8.875 microseconds |
| Ordinary jewel, connected 6230 path | 1615.375 microseconds | 21.750 microseconds |
| Actual 280-radius jewel and remote node | 2083.375 microseconds | 2020.000 microseconds |

The last case retains the same full coverage scan and serves as an unchanged-path
control; its small timing difference is not evidence of an additional optimization.
The first two cases establish the isolated cost of the skipped no-op full-graph
scan. They do not measure full public context validation or whole reward latency,
and these savings cannot be added to nested production timings.

## Reproduce

Run only in the parent's free CPU window, using fresh data/config/cache children
of /tmp/godot-m1-v051-allocation-XXXXXX, with those three XDG environment variables
set explicitly. Set ALLOCATION_V051_OUT to the absolute project path
docs/qa/v051-allocation/result.json and ALLOCATION_V051_TIMING=1. Invoke the
approved /usr/local/bin/godot with --headless --path . --script
tests/empty_radius_allocation_test.gd, capturing output to this folder's run.log.
Use the imported project, never editor/import/GUI.

Require zero process exit, EMPTY_RADIUS_ALLOCATION_COMPLETE, zero reported
failures and no engine/script errors. Preserve any failed first attempt before a
fix/retry. Pure analysis CPU numbers are not reward settlement, rendered frame
performance or Windows FPS.

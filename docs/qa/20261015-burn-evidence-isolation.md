# Burn equivalence evidence isolation — 2026-10-15

## Defect and scope

The pure-rules regression harness previously opened
`docs/qa/v063-settlement-rules/results.json` with `FileAccess.WRITE` on every
successful run. Rerunning a regression therefore replaced historical evidence.
This change affects only test-output handling and its regression coverage.
Production code, frozen oracle preloads, historical evidence, and the
58,593-assertion equivalence workload are unchanged.

## Output contract

- Default output is a fresh directory named
  `/tmp/godot-burn-evidence-<process-id>-<ticks>/results.json`
- Callers may set `BURN_EVIDENCE_DIR` to a new, normalized absolute directory
  below `/tmp`. Its parent must already exist
- The harness atomically reserves that directory with a non-recursive mkdir.
  An existing file or directory is refused, even if it is empty
- Relative, resource, repository, unnormalized, and symbolic-link paths are
  refused. No overwrite option or destructive cleanup is provided
- Invalid/reservation failures emit `BURN_EVIDENCE_ERROR:` and exit 73 before
  the equivalence workload runs
- Successful publication flushes/closes the report and prints
  `BURN_EVIDENCE_REPORT <absolute-path>`. The existing
  `BURN_SETTLEMENT_EQUIVALENCE <json>` summary remains available

The existing Linux/`XDG_DATA_HOME=/tmp/godot-m1-v063-...` isolation guard is
preserved. An optional destination example, using a fresh suffix each time:

```sh
XDG_DATA_HOME=/tmp/godot-m1-v063-burn-data \
XDG_CONFIG_HOME=/tmp/godot-m1-v063-burn-config \
XDG_CACHE_HOME=/tmp/godot-m1-v063-burn-cache \
BURN_EVIDENCE_DIR=/tmp/burn-equivalence-unique-run \
timeout 90 godot --headless --path . \
  --script res://tests/burn_settlement_equivalence_test.gd
```

## Compatibility review

Repository searches found historical README/receipt references to the script
and the old evidence bundle, but no active external caller that consumes the
overwritten file. The existing README invocation continues to work without an
environment override. Historical README, execution receipts, pinned hashes, and
line references remain preserved as records of their original execution;
this note documents the new output contract. New callers should consume the
printed report path or supply a fresh destination.

## Verification

Command: `python3 tests/test_burn_evidence_isolation.py`

Godot: `4.6.3.stable.official.7d41c59c4`

Result: **5 tests passed**, comprising **10 serial Godot invocations**, in
13.523 seconds. Each subprocess has its own 90-second timeout and isolated
`/tmp/godot-m1-v063-evidence-test-...` XDG directories. No editor/import run
or asset cleanup is performed.

Coverage:

1. Default destination publishes fresh, parseable JSON
2. Explicit fresh destination publishes successfully; a second use exits 73
   and preserves the first report byte-for-byte
3. Existing file and symbolic-link ancestor are refused without modification
4. Historical repository directory, resource URI, relative directory, and
   parent-traversal path are refused
5. Missing parent is refused without recursively creating directories

Both successful runs reported exactly **58,593 checks and zero failures**.
All rejection cases exited 73, with the expected diagnostic and no
`SCRIPT ERROR:`. Every invocation checked the SHA-256 inventory of historical
evidence and frozen/source files; the inventory stayed unchanged.
Generated `.uid`/`.import` metadata are excluded from that inventory.

Historical `results.json` SHA-256 before and after:
`dcfc3f137b8cf88fea1e5a9fb657bb5487a8aeefbf8218b0c21c2aa2ae7365e7`.
It also has no Git diff.

Run logs and the explicit report were retained locally under
`/tmp/godot-m1-v063-evidence-test-4m73ztoi/`.
The default report was retained at
`/tmp/godot-burn-evidence-7-203053/results.json`.
These are runtime artifacts, not durable repository evidence.

The unchanged harness still emits its historical direct-call microbenchmark
fields. This verification makes **no current performance, frame-rate, or
gameplay claim** from those timing samples.

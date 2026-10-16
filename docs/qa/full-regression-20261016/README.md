# Full transaction regression — 2026-10-16

## Result

The existing complete profile was actually executed sequentially in the current dot Linux environment: **63/63 cases passed; 82,703 observed and accepted checks; zero failures**, runner exit code 0. All 63 process exits were zero, each exact expected assertion count matched, and all archived logs were reparsed with the unchanged runner. No engine errors were accepted. Warnings, if any, remain in the raw report and verification summary.

The runner's separate fake-executable unit suite also passed **23 tests**. These are harness checks, not added to the 82,703 gameplay assertions.

## Reproduce

Run `python tools/run_transaction_regressions.py --mode full --godot /usr/local/bin/godot --timeout 90` from the repository. Run `python -m unittest discover -s tests -p test_transaction_regression_runner.py -v` for the harness checks.

Godot: `4.6.3.stable.official.7d41c59c4`. Every case retained the existing fresh XDG directory isolation, guard prefixes, strict summary/count/error checks, and 90-second timeout. No concurrent performance benchmark ran. The test run began at approximately 04:25 UTC.

## Baseline and preservation

Local HEAD: `6d3d5755c59c8bdeabdc2f586a070096880bb496`; tree: `7ab9f94c820ccec2279b3bddc4590f73bbc7a13c`. The parent independently verified this tree equals remote main `addd71a6779d8b976e73d9a9c02a0c245cd463aa`; this test worker performed no remote writes or independent remote verification.

All 8,780 pre-existing tracked files were SHA-256 hashed before and after execution, before adding this evidence directory. The two complete manifests were byte-identical: SHA-256 `980438dbc8e69a47761e02d566e08b620e37fad2c2f4544ad7ae82292cf81051`. `tracked-manifest.json.gz` holds that shared manifest, with deterministic gzip timestamp. Existing untracked Godot import/UID sidecars were left untouched and excluded from this deliverable. No production source, fixture, runner or tracked historical evidence was changed.

## Evidence

- `raw/report.json`: original full report, including per-case command, isolation paths, duration, warnings and result
- `raw/*.log`: all 63 original Godot logs
- Other files under `raw/`: original suite-specific evidence reports
- `runner-unit.log`: all 23 harness unit tests
- `verification.json`: baseline, before/after hashes, exit status and independent reparse count
- `SHA256SUMS`: digest of each archived file other than itself

Absolute `/tmp/transaction-regressions-x3h728fh` paths inside raw records are original execution provenance. Their contents are archived under the corresponding relative path in `raw/`; no temporary XDG save is retained. Before/after uncompressed manifests and terminal stdout remain at `/tmp/full-regression-20261016-control` only as additional local working evidence.

## Scope

This is complete coverage of the configured 63-case transaction/startup/UI/purchase/crafting/burn profile, not every test in the repository. It does not establish Windows/native rendering, Windows FPS, performance improvement, CI, packaging, or remote publication/merge. The outstanding high-density performance issue is not resolved by these correctness checks.

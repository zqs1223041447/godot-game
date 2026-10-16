# Integrated full profile — 2026-10-16

## Result

The final expanded profile was actually executed sequentially in the current dot Linux environment: **68/68 cases passed; 83,206 observed and accepted checks; zero failures or warnings**. Runner exit code 0; all 68 subprocess exits were zero; all expected counts matched. All 68 original logs were reparsed using the current runner after execution. No engine errors were accepted.

The current fake-executable runner unit suite independently passed **25 tests**. These harness checks are not added to the gameplay assertion count. The earlier 63-case evidence is unchanged and is not counted as additional unique coverage here.

## Method

Command: `python tools/run_transaction_regressions.py --mode full --godot /usr/local/bin/godot --timeout 90`.

Harness command: `python -m unittest discover -s tests -p test_transaction_regression_runner.py -v`.

Godot `4.6.3.stable.official.7d41c59c4`; existing sequential fresh-XDG isolation, guard prefixes, strict summary/error/exact-count validation and per-case 90-second timeout retained. No concurrent performance benchmark ran. The new five cases actually ran within this integrated sequence: pending-death boundary 107, canonical state 27, combat pipeline 305, ember clock 45, same-time burn cleanup 19 (503 checks). The 107-check boundary case used its fresh evidence output directory. Quick profile remains configured as 15 cases/1,414 checks; this execution used full only.

## Working-tree baseline and preservation

This is acceptance of the working tree, **not the unmodified HEAD alone**. HEAD at start was `6d3d5755c59c8bdeabdc2f586a070096880bb496`, HEAD tree `7ab9f94c820ccec2279b3bddc4590f73bbc7a13c`. Three tracked paths already differed from HEAD: `tools/run_transaction_regressions.py`, `tests/test_transaction_regression_runner.py`, and `docs/ACTIVE_WORK.zh-CN.md`. Their exact working bytes, together with all other tracked files, were captured in the before manifest. Runner and unit-file SHA-256 are also explicit in `verification.json`.

All 8,780 tracked working files were hashed before and after execution, before adding this evidence directory. Complete manifests are byte-identical: SHA-256 `c0a5fd54cb7e64c255d74975424d4c9174f4df34d6a02232fd626dda1331f029`. `tracked-manifest.json.gz` contains that common manifest with deterministic gzip timestamp. The after snapshot was captured at 04:47:22 UTC; parent documentation edits after this timestamp are outside this preserved execution window.

No production, runner, fixture or tracked historical evidence changes were made by this test worker. Existing untracked Godot import/UID sidecars were excluded and left untouched. No commits or remote writes were performed by this worker.

## Evidence

- `raw/report.json`: original per-case results, commands, isolation paths, timing and warnings
- `raw/*.log`: all 68 original Godot logs
- Other files under `raw/`: original suite-specific evidence, including pending-death boundary report
- `runner-unit.log`: 25 harness tests
- `verification.json`: working-tree baseline metadata, exit code, matching hashes and reparse count
- `tracked-manifest.json.gz`: complete shared before/after tracked-file SHA-256 map
- `SHA256SUMS`: digest of each other archived file

Absolute `/tmp/transaction-regressions-vhwrx7zs` paths are original execution provenance; preserved contents are under corresponding relative paths in `raw/`. Disposable XDG saves are not retained. Terminal stdout and uncompressed hash snapshots additionally remain in `/tmp/integrated-regression-20261016-control` as local temporary evidence.

## Limits

This is the complete configured 68-case profile, not every repository test. It does not establish Windows/native rendering, Windows FPS, a performance improvement, CI, packaging or remote publication/merge. High-density performance remains unresolved. Prior and current overlapping runs must not be summed as unique functional coverage.

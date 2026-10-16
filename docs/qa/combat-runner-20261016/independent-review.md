# Independent combat runner review — 2026-10-16

## Conclusion

No blocking finding in the reviewed runner and unit-test changes. Approval is limited to the five-case integration and harness safeguards described below. No production implementation, existing GDScript test, or fixture was edited by this reviewer.

Reviewed SHA-256:

- `tools/run_transaction_regressions.py`: `0cb5ac8637d33b3387a19d43f76754f01347479086342826cd6ae96838c41a76`
- `tests/test_transaction_regression_runner.py`: `08bb4ef822f6c8e8bb3c082d3576fb24c5b2e3625bfa7ea4e1cd32ab45946e3f`

## Independently executed

`python3 -m unittest discover -s tests -p test_transaction_regression_runner.py -v`: **25/25 passed**, 4.316 seconds. These use fake executables, not gameplay assertions.

Imported the current runner and called `run_case` sequentially with `/usr/local/bin/godot`, the current project, a newly created `/tmp/combat-runner-independent-CvtfTQjf` output directory, and the unchanged 90-second limit:

| Case | Checks | Result |
|---|---:|---|
| map_pending_death_boundary | 107 | PASS |
| canonical_game_state | 27 | PASS |
| combat_pipeline | 305 | PASS |
| ember_event_clock | 45 | PASS |
| burn_same_time_cleanup | 19 | PASS |

All five exited zero, produced the exact single expected summary, and had zero failures or warnings: **503 checks**, 12.816 seconds combined (not a performance claim). Each case used fresh disposable XDG data/config/cache directories. The reviewer deliberately supplied inherited `EXPLORATION_MAIN_OUTPUT`, `EXPLORATION_MAIN_INPUT_ONLY=1`, and `EXPLORATION_MAIN_SAVE_ONLY=1`; the historical output directory's sentinel remained unchanged and no file was added there. Fresh retained map evidence was produced separately. Raw logs, the actual per-process report, map output, historical sentinel and unit log remain in the above temporary directory. They are additional local reviewer evidence, not newly archived copies of the integrator's logs.

No competing Godot test process was visible before the run. The reviewer notified the integrator immediately after these five runs and performed no additional Godot execution, leaving the slot available for final integrated acceptance.

## Static and negative-path review

- The map output uses `tempfile.mkdtemp` under the retained output directory, providing an atomically reserved, existing, unique directory rather than reusing inherited or historical output. It remains outside the disposable XDG directory.
- All three exploration switches are removed from the copied child environment before case configuration; parent environment is unchanged.
- Existing summary parsing, exactly-one-marker enforcement, integer/exact count checks, nonzero exits (including guard exit 78), engine-error rejection, process-group kill on timeout, and timeout validation remain intact. Warnings remain disclosed rather than newly treated as errors, matching baseline behavior.
- The new tests reject absent/duplicate summaries, too few or too many assertions, positive failures, trailing junk, engine errors, and nonzero/guard exits for every new case. Existing timeout tests also pass. Two fake runs verify unique retained output, non-overwrite and XDG cleanup.
- Full quick-case configuration compared against `HEAD` is identical apart from the new inert default dataclass field: **15 cases / 1,414 checks**. Current full matrix is **68 cases / 83,206 checks**; the five additions contribute exactly 503. The previously tested two burn cases are still explicitly checked even though a third burn-named case now exists.
- Map count 107 intentionally includes successfully opening the output file; its real run with the fresh directory confirms this contract. No output means a different assertion count and is not an acceptable replacement.

## Evidence checked without re-executing those suites

Using the current parser, independently reparsed and matched the archived reports for:

- `../full-regression-20261016/raw/`: 63 cases / 82,703 checks
- `../combat-regression-20261016/`: five cases / 503 checks
- This directory's integrator logs: five cases / 503 checks

All 77 entries of `../full-regression-20261016/SHA256SUMS` match their archived file bytes. This verifies archive consistency, not an independent recreation of its prior execution or before/after source snapshots.

The historical 63-case run and separate five-case runs are **not** a single execution of the changed 68-case runner. Because environment cleanup changed globally, the integrator is scheduling a separate final integrated 68-case run. Its result must be reported separately; it was not yet available when this review was written. No claim is made for all repository tests, CI, native Windows rendering/FPS, packaging, remote publication, or resolution of PERF-001.

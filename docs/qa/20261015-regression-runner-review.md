# Independent runner review

Reviewed 2026-10-15: tools/run_transaction_regressions.py, tests/test_transaction_regression_runner.py, docs/TRANSACTION_REGRESSION_RUNNER.zh-CN.md and actual selected GDScript contracts. No source changes, Git writes, or Godot launches performed.

## Findings requiring correction

- Non-JSON parser uses an unanchored search. A malformed summary such as `FAKE: -3 checks, 0 failures` is parsed as 3/0; `FAKE: checks=3 failures=0.5` is parsed as 3/0. Anchor the accepted grammar, allowing only the known gem catalog prefix. Add malformed-summary tests.
- Diagnostic improvement: real guard exits generally print no summary, so reason currently becomes summary_error rather than guard_rejected. Exit 78 does fail acceptance correctly; preserve its specific diagnosis before summary parsing.

Worker and parent notified directly.

## Verified

- All 12 Python unit tests pass (0.385 seconds). These fake-executable checks are not game acceptance.
- Independent fake executable spawning a sleeping child was timed out after 0.3 seconds. Parent and descendant were both terminated; descendant /proc entry absent afterward. Correct use of start_new_session and killpg ensures same-group descendants are killed. Timeout remains failure even after a success summary.
- Independent fresh /tmp directories for all XDG roots on each run; scenario and report/capture switches cleared; process environment copied rather than mutated. Current script switches match all sanitized variable names.
- Prefix contracts match actual scripts: atomic/group/store/support accept godot-m1-; UI accepts godot-ui-feedback.; picker accepts godot-owned-gem-picker-; binding accepts godot-skill-binding-; safe exit accepts godot-m1-v099-; return/F6 accept /tmp/. Gem catalog is a pure suite and has no save guard.
- Picker/binding inherited PATH is user://build_save.json; inherited run() is overridden, so base flask-purchase guard is not applicable. Screenshot methods return immediately under headless, so cleared capture variables cannot write screenshots to unintended locations.
- JSON report destinations are explicit per-case files under the new evidence directory. Safe exit honors SAFE_EXIT_OUTPUT. Other selected suites write user:// data only or do no writing. No selected suite uses historical QA output paths.
- Fresh mkdtemp evidence directory and unique built-in case names prevent CLI collisions. Programmatic reuse of output_dir and case name would overwrite its own log, but CLI never exposes this path option.
- Error tokens cause failure even with exit zero; warnings recorded separately; nonzero and 78 fail; strict expected totals reject smaller and larger counts; duplicate matching summary lines fail.
- Report accepted_checks excludes any failed run. Documentation explicitly distinguishes assertion executions from unique requirements and quick from full matrix.
- Full matrix contains 37 unique case names; quick has 13, subset of full; return matrix 387 checks and F6 matrix 163 checks.
- Timeout cap is per process, not whole run, and documentation makes this distinction. Existing Python test does not test descendants; independent reviewer check above supplements it.

## Limits

Godot quick/full execution and actual baseline counts are owned by the implementation worker. Review does not independently certify runtime acceptance. No CI outcome claimed. Repository has many pre-existing untracked generated files; publication must continue using an explicit file allowlist.

## Re-review 13:26 UTC: approved

Both findings corrected: non-JSON summary uses re.fullmatch on stripped tail; catalog marker explicitly includes `10 skills, 24 supports;`; exit classification precedes summary parsing so guard 78 without summary retains guard_rejected. New tests cover malformed numeric suffixes and summary-free guard. All 14 tests pass (0.386 seconds). No remaining blocking findings in reviewed scope. Runtime worker should reparse saved full-mode logs with final parser, since active run began before parser-only fix.

# Live production combat regression runner integration — 2026-10-16

## Scope and results

Only the standard-library runner and its Python tests changed. Five existing Godot suites are now full-mode cases. The quick matrix remains byte-for-byte equivalent in its existing case fields: **15 cases / 1,414 assertions**. The configured full matrix is **68 cases / 83,206 assertions**.

This batch actually executed **five newly integrated cases / 503 assertions**, sequentially, through `run_case`, and **25 Python unit tests**. All passed. It did not rerun the entire 68-case matrix or any performance benchmark. The separate earlier 63-case / 82,703-assertion run is documented in `../full-regression-20261016/`; these results must not be described as one uninterrupted 68-case run. No performance improvement, Windows/native visual acceptance, or CI pass is claimed.

| Case | Assertions | Summary marker | Isolated XDG prefix |
| --- | ---: | --- | --- |
| map_pending_death_boundary | 107 | `MAP_PENDING_DEATH_BOUNDARY ` | `/tmp/godot-m1-map-death-boundary-` |
| canonical_game_state | 27 | `Canonical game state:` | `/tmp/godot-m1-transactions-` |
| combat_pipeline | 305 | `Combat pipeline:` | `/tmp/godot-m1-transactions-` |
| ember_event_clock | 45 | `Ember event clock:` | `/tmp/godot-m1-v050-` |
| burn_same_time_cleanup | 19 | `Burn same-time cleanup:` | `/tmp/godot-m1-v050-` |

Each script is `tests/<case>_test.gd`. The map test validates controlled final-descendant refusal/recovery boundaries with real production state, not natural combat footage. The pipeline case tests production modules directly; not all five instantiate the playable Main scene.

## Evidence isolation and failure behavior

The map suite inherits `exploration_main_flow_test.gd:write_json`. Without `EXPLORATION_MAIN_OUTPUT`, evidence writing is skipped and its count is only 106. With a writable existing directory it performs the required 107th assertion and writes `pending-death-boundary.json`. That writer would overwrite an existing file.

The new generic `fresh_evidence_env` case field therefore reserves an already-created, unique retained evidence directory using `tempfile.mkdtemp`, outside disposable XDG storage. Reusing the runner output directory still creates another destination. Existing suite-reserved `evidence_env` and file-based `report_env` behavior stays unchanged. Inherited `EXPLORATION_MAIN_OUTPUT`, `EXPLORATION_MAIN_INPUT_ONLY`, and `EXPLORATION_MAIN_SAVE_ONLY` are removed before per-case configuration. Historical outputs cannot redirect this suite.

Unit tests cover all five exact contracts, full-only selection, fresh empty XDG, exact executable arguments, cleared inherited switches, missing/duplicate/malformed summaries, incorrect counts, assertion failures, engine errors, nonzero/guard exits, and preservation across repeated map evidence writes. Existing timeout tests retain the >0 and <=90-second bound, including success output followed by timeout. Parser, exit/error checks, process-group termination, and timeout implementation are unchanged.

## Reproduction and retained evidence

Python tests:

```sh
python -m unittest discover -s tests -p 'test_transaction_regression_runner.py' -v
```

The five-case run selected the above names from `cases('full')` and invoked `run_case(case, '/usr/local/bin/godot', ROOT, output_dir)` sequentially with the default 90-second bound. `report.json` records exact commands, temporary XDG paths, observed counts, return codes, durations and retained evidence destination. Per-case `.log` files and the map's JSON evidence are beside this report. `python-units.log` records the Python run.

`preservation.json` records a before/after SHA256 comparison of 7,898 tracked files under scripts, scenes, tests and historical docs/qa, excluding the intentionally edited Python runner test. No differences were found. It also records exact comparison of old quick-case contracts with current contracts (ignoring the new default-empty field). The parent-owned ACTIVE_WORK update is outside this preservation scope. Generated/untracked import metadata is not included in that claim.

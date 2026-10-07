# v095 first diagnostic attempt: stopped

The runner stopped at the first `ERROR`, killed the clean process, and did not
start the instrumented process. No retry was made before reporting the failure.

- Base: `eaf298a8cbd22c8387da28da118a15afdcd2afb5`
- Command: `python3 tools/diagnostics/run_v095_burn_profile_audit.py`
- Planned per-process range: ember frames 0–19; no-burn frames 0–3
- Completed: clean ember frames 0–19 plus final save
- Stopped: no-burn fixture's fresh initial save
- First error: `ERROR: Fresh diagnostic save rejected`
- Runner termination: SIGKILL, exit code -9, 11.7868 seconds
- Evidence: `clean.txt`, `run_manifest.json`, `clean.json`, and the
  `clean-ember_deaths` observation/final/save files

The old diagnostic used `user://build_save.json` for both fresh models. The
current canonical store's `_persist` rejects a new model's save to an existing
path (`scripts/save/canonical_build_store.gd:523–525`). The parent authorized
isolating each mode in its own process/XDG directory while retaining the exact
`user://build_save.json` path, because production reward/migration gates can
depend on that path. The completed clean ember case was verified and reused;
only clean no-burn, instrumented ember and instrumented no-burn were run after
approval. No production persistence guard or save-path semantic was changed.

The incomplete clean run's peak was frame 0: 831.212 ms, 342 hits, 100 burns,
100 enemies, zero kills. Frame 16 had 13 kills and frame 17 had 7 kills. These
are preliminary event/tick observations only. There is no accepted profile
attribution or performance conclusion because the paired run did not complete.

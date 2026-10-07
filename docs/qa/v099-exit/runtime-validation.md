# v099 safe map exit: targeted integration evidence

The first execution passed **120 checks, 0 failures**, with Godot exit status 0.
No test failures, retries, or broader-suite runs were omitted from this record.

## Inputs and method

- Base checkout: `d7e4121`; production Main and HUD changes were present as working-tree edits
- Engine: Godot 4.6.3 stable (`7d41c59c4`), headless Linux
- Actual `main.tscn`, Main, GameHUD, and CanonicalGameState; the Main subclass overrides only `_quit_game` to count requests
- A CanonicalGameState subclass fails designated `_write_bytes` calls. Successful calls use the real atomic writer
- Fresh isolated `XDG_DATA_HOME`; the suite refuses an existing initial normal save or a path outside `/tmp/godot-m1-v099-*`
- Old Garden tier I is drafted and entered through the real transaction APIs. Controlled damage clears its 25 roots and bounded descendants through actual death, progression, and completion handling
- No completion flag, earned currency, tier unlock, encounter roster, timer, or RNG state is granted. This is controlled integration evidence, not natural-combat footage

The complete command, isolated directory, UTC start/end times, and SHA-256 hashes
of Main, HUD, CanonicalGameState, canonical store, and test are recorded in
[first-inputs.json](first-inputs.json). All five hashes were checked unchanged
after execution. The shared project import completed before this suite; this
worker performed no additional import.

## Results

| Group | Checks | Failures | Proven boundary |
| --- | ---: | ---: | --- |
| `town_and_reentry` | 32 | 0 | Persistent ordinary-save failure retains the game; recovery saves/quits once; reentry from the active writer returns busy; repeated direct/menu/window requests cause no more writes or quits; both prior SceneTree quit settings restore on removal |
| `unfinished_map` | 14 | 0 | Menu exit keeps unfinished entry semantics; actual reload abandons the unfinished run without inventing unlocks or rewards |
| `completion_recovery` | 35 | 0 | Real completion-write failure retains the retry receipt; ordinary save remains ordinary; repeated failed HUD exits retain the game and show failure; recovery commits completion; reload retains the tier and pending reward; claim credits exactly four once and stays consumed on another reload |
| `partial_commit` | 38 | 0 | Window close commits completion before the deliberately failed second write; pending is not reinstated; persisted completion remains readable; further failures retain it; retry only saves progress and never remints reward; actual reload/claim is exactly once |
| Requested-group guard | 1 | 0 | An unknown test selection cannot silently report success |

Raw evidence: [first-run.log.txt](first-run.log.txt), [first-result.json](first-result.json).
The observed failures in production persistence are deliberate fault injections
and were correctly rejected. The test harness itself had no failed assertions.

## Reproduction

After the normal shared Godot project import, run:

```sh
XDG_DATA_HOME="$(mktemp -d /tmp/godot-m1-v099-exit-XXXXXX)" \
  /usr/local/bin/godot --headless --path . \
  --script res://tests/safe_map_exit_test.gd
```

`SAFE_EXIT_GROUP` can select exactly one group listed above for an affected-group
rerun. `SAFE_EXIT_OUTPUT` optionally names a JSON result file. No rerun was needed
for this first passing implementation. No native window-manager event delivery,
Windows package, performance, or natural-combat result is claimed by this suite.

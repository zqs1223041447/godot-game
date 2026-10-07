# v0.86 actual Main exploration evidence

`tests/exploration_main_flow_test.gd` starts the default scene with a fresh formal character and the real `user://build_save.json` path. It opens all four tier-I maps through `craft_normal_map` and `start_map`, checks each complete initial roster, and completes old_garden by killing the natural boss before any ordinary root. Controlled deaths use the normal defense/death/reward path; retained children delay completion. Earned tier-I rewards then fund a real tier-II entry. No gear, currency, or unlock is manufactured.

The test deliberately pauses automatic frame processing and advances Main ticks itself. Status, opposite-wall positions, and deaths are controlled QA probes, not recordings of natural combat. The fresh entry, movement input, mouse state, shield recovery, birth protection, freeze, burn, external forces, separation, chase, completion, return, claim, and paid reentry use actual Main consumers. A subclass loaded from the earned save injects only a write failure, proving fee, save, runtime ID, actor, record, geometry and camera atomicity. The unknown-route probe verifies that unsupported future rewards do not fall back to standard settlement.

Run only after the shared import pass, with a NEW isolated data directory whose prefix is `/tmp/godot-m1-v086-exploration-`. Set `EXPLORATION_MAIN_OUTPUT` to this evidence directory for `main-result.json` and `formal-final-save.json`. The launcher should stop immediately on `SCRIPT ERROR`; do not hide a parse/runtime failure behind a long timeout.

The separate camera test owns the resolution and boundary matrix. This suite only checks actual Main entry, movement and return camera consumers.

## Acceptance and preserved attempts

`acceptance.json` records accepted core Main gameplay coverage. The original complete run executed 245 assertions in 7.675 seconds: 244 passed, and one synthetic mouse-coordinate assertion failed. All four entries, the complete boss-first old_garden flow, descendant cleanup, normal rewards, paid reentry and atomic rejection checks passed. `main-result.json` deliberately retains its original `failures: 1`; it has not been rewritten to imply a clean full rerun.

The focused diagnostic identified a fixture error: the headless native window is 64×64 while the logical viewport is 1280×720. Sending logical mouse `(800,335)` directly to `Input.parse_input_event` incorrectly produced viewport `(16000,6420)`. The test now transforms logical cursor coordinates through `root.get_screen_transform()` before submitting native events, and releases with a new event object. No camera or other production code changed for this correction.

The final focused input run uses `EXPLORATION_MAIN_INPUT_ONLY=1`. It executed 10 checks in 4.332 seconds with no failures or logged errors, using the same default Main and legal tier-I entry. Native `(40,30.75)` correctly becomes logical `(800,335)`, expected and actual global mouse both equal `(2092.154,1304)`, and the real aim is `(1,0)`. This closes the original failed assertion; the overlapping checks are not counted as 255 independent scenarios. The unaffected 244 passing assertions were not rerun.

The first complete log, the intermediate diagnostic log, and the successful focused log remain in `docs/qa/v086-integration/main-attempt01.log.txt`, `main-input-attempt02.log.txt`, and `main-input-attempt03.log.txt`, with their matching result JSON files. `acceptance.json` compares all six production-file hashes from `main-attempt01-inputs.json` with the current files and records that they are unchanged. It also verifies the final test script matches the successful focused-run hash.

## Interactive native entry

Launch `docs/qa/v086-gameplay/native_review.gd` with a fresh `XDG_DATA_HOME` beginning `/tmp/godot-m1-v086-exploration-native-`; optionally set `EXPLORATION_NATIVE_MAP` to any of the four map IDs (default `ginkgo_arcade`). This fixture calls the same actual tier-I town/draft/start path and then leaves all normal processing enabled. It does not reposition or freeze enemies, change health, grant equipment, or alter progression. Move with the normal game controls, aim/fire with the mouse, and use the normal map return controls. The entry lies southwest; the first group is north/northeast, other groups are farther north and east, and the boss starts northeast. Screenshots from this entry are interactive native evidence; screenshots are not required for the controlled integration result.

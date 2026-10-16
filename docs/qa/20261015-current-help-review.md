# Current Help independent review

Result: PASS, no blocking findings in the reviewed batch.

Reviewed branch `dot/20261015-current-help`, base/HEAD `d606de670772c38a373ffd86fec389187f372983`, working changes in `scripts/game_hud.gd` and new `tests/current_help_contract_test.gd` on 2026-10-15 UTC. No repository edits or editor import performed by this reviewer.

## Contract checks

- Input dispatch (`main.gd:581-619`) resolves canonical per-row bindings before legacy numeric fallback. K opens the skill panel and its binding action calls canonical `bind_group`; the replacement binding-led instruction is correct. Alt+1–5 is explicitly intercepted for flask slots. Existing movement, mouse, Q, Space/dash, panel and F8 instructions remain supported.
- Capacity (`canonical_game_state.gd:169`) is 10 plus compiled `additional_skill_slots`. Rendering the live method result avoids the obsolete five-skill limit and accurately reflects equipped capacity. Only a local string/read-only capacity query was added; no input, gameplay, persistence, layout or style implementation was changed.
- Jewel policy (`rewards/kill_reward_policy.gd`) increments eligible reward kills and awards ordinary jewels every 20; nonrewarding descendants and demos do not advance it. `restart_run` resets `reward_kills` to zero. Boss rarity separately requests a special jewel. “本轮” distinguishes this from persistent formal 30/60 gem/flask milestones. “可获得” correctly avoids guaranteeing delivery when capacity/save limits prevent it (`main.gd:1934-1957`). These policies also apply to eligible practice/test roots.
- Persistence includes canonical build and formal journey state, including normal root kills and map progress. Practice uses the normal profile. Entering test town saves normal progress first and uses a separate test save with initially empty journey (`main.gd:2739-2770`). The footer is a general save/restart statement; it does not say test play advances the formal journey. Its fee clause explicitly concerns formal maps, so it does not assign fees to practice or test play.
- Formal retries use the current map profile, call canonical `normal_start_map`, and atomically subtract the profile fee with the new journey (`main.gd:3085-3092`, `canonical_game_state.gd:1298-1322`). This naturally includes a zero-fee current map. Restart resets live combat and preserves the build.

## Fixture quality and independent execution

The new test instantiates the actual main scene and current canonical model. It persists a real custom F1 binding, checks the old numeric binding was removed, generates/equips a real catalog additional-row item, observes capacity 10 then 11, and transitions through real formal-town, practice, and separate-test-profile APIs. There is no fake model or method substitution. It compares canonical snapshots, both save files, and run/world revisions across Help opening/closing.

Command used:

    prefix=$(mktemp -d /tmp/godot-current-help-review-XXXXXX)
    timeout 90s env XDG_DATA_HOME="$prefix/data" XDG_CONFIG_HOME="$prefix/config" XDG_CACHE_HOME="$prefix/cache" godot --headless --path . --script res://tests/current_help_contract_test.gd

Actual prefix: `/tmp/godot-current-help-review-lazRaP`.
Godot 4.6.3; exit 0; `Current Help contract: 163 checks, 0 failures`.
Log: `/tmp/current-help-review-test.log`.

Coverage is logical viewport/modal/footer/scroll-width checks at 1280×720 and 2560×1440, font scales 1.0/1.2 and UI scales 1.0/1.1. This is not native screenshot/Windows visual acceptance or an independent rerun of the wider gameplay suite. Retry/reward semantics were source-reviewed, not newly simulated by this focused test. The unused Model preload is harmless.

The worktree already contained many untracked generated .uid/.import sidecars on entry. They are outside this review's two-file scope and should not accidentally enter the publication tree.

## Final-delta recheck

The worker subsequently clarified boss wording to “击败原始首领另可获得” and added two legacy-adapter assertions. Re-reviewed the final source/test. The fallback uses a real `build_state.gd` object only for the HUD state adapter while retaining Main's canonical world API. It checks generic rows instead of inventing a capacity and checks legacy snapshot/canonical save bytes remain unchanged. This deliberately narrow fallback check is meaningful; it does not pretend to exercise a fully legacy Main runtime.

Independently reran the final version with a NEW prefix `/tmp/godot-current-help-review-final-3sCqZx`, the same 90-second timeout, and no editor import. Result: exit 0, `Current Help contract: 165 checks, 0 failures`. Final log: `/tmp/current-help-review-final-test.log`. Final verdict remains PASS with no blocking findings. The earlier 163-check run is superseded, not added to the final assertion count.

## Viewport clarification (2026-10-15 follow-up)

The 1280×720 and 2560×1440 values above are requested physical root-window sizes. Under this project’s canvas_items stretch configuration, the tested Main scene retains a 1280×720 logical viewport (HUD local size also changes with UI scale). These checks do not establish an independent 2560×1440 logical layout or native rendered 2K acceptance. The later keyboard-scroll regression explicitly records and asserts the actual logical viewport.

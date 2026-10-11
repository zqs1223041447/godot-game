# Focused combat fixture repair

2026-10-11 · Godot 4.6.3 headless · production HEAD `76782a468b986a32142bc58a6be358aad985f1d0`

Only `monster_integration_test.gd` and `flask_gameplay_test.gd` changed. No production logic, assertion thresholds, reward rates, or damage executors changed. This is controlled integration evidence, not natural gameplay or rendered QA.

## Cause and repair

- Monster: the legacy BuildState injected into current Main lacks the normal-journey and trade APIs. A canonical fresh save now loads through normal scene startup, and `leave_normal_town` publicly admits the existing arena tests. The old jewel serial observation is replaced by the entire canonical snapshot, retaining and strengthening the no-progression check. Automatic HUD processing is disabled by this fixture; after restart it now explicitly runs the real HUD next-frame handler to release the death latch. Existing reward, duplicate corpse, AoE, projectile explosion, shield, attack speed, cap/FIFO, death/restart, F7 and demo assertions are retained. Scene teardown is awaited to avoid exit resource leaks.
- Flask: Main now starts in safe town, where combat flask use is intentionally refused. The fixture enters the isolated test profile through `enter_town_test`, drafts old_garden, and calls `start_map`. Historical 60-kill random gem/flask expectations belong to that profile. Moves and reload use its actual save path, with a separate byte-for-byte check that the formal save is unchanged. The reward probe damages an actual admitted normal root, preserving its authoritative source record. The original RNG/reward oracle is unchanged. A real admitted boss is killed in demo mode, then its exact four real rewardless descendants are killed with demo mode disabled. This retains zero-reward coverage without inventing map source bindings or setting actor reward flags. A terminal sentinel prevents a script exception inside the reward helper from appearing as success.

Controlled fixture values remain explicit: disabled automatic frame processing/autofire, set resource levels and reward counter 59, deterministic reward RNG, expired spawn protection, direct damage calls and explicit ticks. These are not claims that 60 natural kills occurred. Actors, map admission, damage/death settlement, item grants, save transactions and descendant creation execute production paths.

## Results and evidence

- Monster before: 85 checks, 18 failures, script exceptions; after: 89 checks, 0 failures
- Flask before: 61 checks, 10 failures, script exception; after: 82 checks, 0 failures
- Both final processes exit 0, with no `SCRIPT ERROR:`, `ERROR:` or `FAIL:` lines
- `git diff --check` passes

The four `*-before.log` / `*-after.log` files preserve raw current-HEAD runs. `comparison.txt` lists summaries and original failure labels. Earlier frozen-Main failures are documented separately in `../standard-reward-policy/README.md`; those historical results are not relabeled as repaired runs.

Checks are individual assertion executions, including per-item and per-descendant loops, not independent scenarios. More checks result both from new admission/isolation guards and old statements now reached beyond exceptions. Monster still has the same seven `_case` scenarios. These counts do not mean broad/full-suite coverage.

## Reproduce only these two checks

From the repository root, run this bounded pair in a subshell. Any process failure, error label, or unreadable log fails the command:

```sh
(
  for t in monster_integration flask_gameplay; do
    isolated=$(mktemp -d /tmp/godot-m1-fixture.XXXXXX) || exit 1
    status=0
    XDG_DATA_HOME="$isolated/data" XDG_CONFIG_HOME="$isolated/config" \
    XDG_CACHE_HOME="$isolated/cache" timeout 90 godot --headless --path . \
      --script "res://tests/${t}_test.gd" > "$isolated/run.log" 2>&1 || status=$?
    cat "$isolated/run.log" || exit 1
    [ "$status" -eq 0 ] || exit "$status"
    scan_status=0
    grep -nE 'SCRIPT ERROR:|ERROR:|FAIL:' "$isolated/run.log" || scan_status=$?
    # grep exit 1 means no matches; matches and read errors both fail.
    [ "$scan_status" -eq 1 ] || exit 1
  done
)
```

Each run uses independent disposable XDG data/config/cache. No full suite, graphics rerun, export, network operation or commit was performed. This repair does not cover natural input timing, graphics, every map/profile, formal milestone economics, corrupted-save recovery, or save-write failure/retry boundaries. Existing reward-policy equivalence evidence is not rerun or claimed here.

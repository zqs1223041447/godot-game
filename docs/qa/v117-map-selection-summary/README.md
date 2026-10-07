# v117: explicit unprepared map summary

Base: `4973b4e386a3c43d9fc8e1e097d15b2e20f5595d`.
Independent branch: `codex/v117-map-selection-summary`.

The only production change is `scripts/ui/town_service_panel.gd`: dirty map,
tier or modifier controls show `配置已更改 · 请准备地图`. They no longer display
an old draft's name, cost or reward beside an unprepared new selection. Changing
controls queues the existing deferred status refresh. Successful preparation
restores the authoritative draft summary. Launch authorization is unchanged.
The developer's supplied production edit was not modified during QA.

## Focused actual-panel check

`tests/map_selection_summary_test.gd`: **28 checks, zero failures, exit0**.
Godot4.6.3, headless, one fresh isolated current-schema Main and real town panel.

- Actual map OptionButton change displays only the new dirty message
- An actually unlocked tier change, normal modifier and special modifier each
  display the same message and retain the disabled launch guard
- A real canonical claim changes balance0→4 while a different selection is
  dirty; refresh preserves the selection/message and does not change the draft
- Closing/reopening restores the current authoritative draft and its cost
- The actual prepare button selects 遗迹庭园 I and restores its0-cost/4-reward
  summary, then enables launch
- Reopening now retains that newly prepared draft
- The actual launch button enters the native map with25 roots, closes the panel
  and preserves the existing four-shard balance

Fixture setup uses existing canonical start/complete calls only to provide an
unlocked old-map tierII and a pending four-shard receipt. These are controlled
UI boundary data, not physically earned combat. No old save is loaded, and no
migration suite,174-check entry suite, combat, screenshot, export or asset
rendering is run. Existing imported caches are copied locally and not committed.

## Reproduce

Use fresh XDG directories; the test rejects an already populated save:

```
mkdir -p /tmp/godot-m1-v117-summary-NEW/{data,config,cache}
XDG_DATA_HOME=/tmp/godot-m1-v117-summary-NEW/data \
XDG_CONFIG_HOME=/tmp/godot-m1-v117-summary-NEW/config \
XDG_CACHE_HOME=/tmp/godot-m1-v117-summary-NEW/cache \
godot --headless --path . --script res://tests/map_selection_summary_test.gd
```

`panel-test.log`, `exit-code.txt`, `result.json` and `tested-inputs.json` retain
the exact result and tested source hashes. This is a focused UI regression
check, not a repository-wide regression or rendering/performance result.

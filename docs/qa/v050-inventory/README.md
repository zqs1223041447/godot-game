# v0.50 inventory/reward CPU diagnostic

Source baseline: v0.49 (`a9a402d`). The diagnostic lives at `tools/diagnostics/inventory_reward_profile.gd`. It does not modify production sources. One isolated run completed on 2026-10-05 using `/usr/local/bin/godot` 4.6.3, the headless display server, and the parent audit's free CPU measurement window. Process exit was 0; [profile.log](profile.log) contains the completion marker and no errors. [profile.json](profile.json) holds all observations.

## Observed synchronous CPU costs

| Production action | Time | `changed` | Panel refreshes | Craft metadata calls |
|---|---:|---:|---:|---:|
| 20 normal root deaths, bag closed, including final flush | 33.654 ms | 23 | 0 | 0 |
| First I opening | 43.731 ms | 0 | 1 | 1 |
| Select legal magic equipment | 3.746 ms | 0 | 0 | 1 |
| Warm reopen 1 / 2 / 3 | 0.393 / 0.316 / 0.242 ms | 0 each | 0 each | 0 each |
| Select damage target | 0.055 ms | 0 | 0 | 0 |
| Request targeted quote and show confirmation | 8.125 ms | 0 | 0 | 0 |
| Confirm and persist one visible targeted craft | 18.593 ms | 1 | 1 | 1 |

The canonical state contained 40 registered items before the reward burst and 43 afterward, including items outside the bag. Death/reward work before the final flush took 27.904 ms; the flush took 5.667 ms. Inclusive subcosts were 4.735 ms for twenty normal XP updates, 13.543 ms for two equipment awards, 3.609 ms for one jewel award, and 2.241 ms for full save validation/serialization/write. The atomic write itself was 0.085 ms. These are overlapping parts of the 33.654 ms total, not additional costs.

Cold opening constructed the lazy production panel. Its metadata call took 0.130 ms with no selection; first item selection's metadata took 2.305 ms. Three unchanged warm reopens performed no panel refresh or metadata call. The target choice changed no model data and issued no quote. The actual quote cost 6.786 ms inside its 8.125 ms request. Craft execution cost 18.298 ms inside its 18.593 ms confirmation, including a 12.207 ms commit and one 1.954 ms metadata call from the resulting visible refresh. Craft persisted once (0.093 ms atomic write), advanced the crafting revision once, and debited real bag shards from 100 to 84; reloading reproduced the exact snapshot. The main HUD refresh recognized the crafting save receipt and made no second save attempt.

These observations do **not** support treating dropdown reconstruction as a cost on every combat hit. In the measured death burst the lazy inventory panel did not exist, so all 23 model changes did zero inventory work. With the inventory open, the production `main._process` entry returned without advancing elapsed time, simulation accumulator, shots or kill counts. In this visible sequence, metadata/dropdown reconstruction happened once for initial panel construction, once for item selection and once for the craft's model change. The source also makes a constructed hidden panel dirty without immediately refreshing it (`canonical_inventory_panel.gd::_on_model_changed`); this run did not measure a second reward burst after closing a previously constructed panel.

It uses one production root, its actual HUD and its lazy canonical inventory panel. Fixture setup adds one legal current-serial magic Cinder Reed and 100 actual bag calibration shards to the current canonical starter inventory, validates the full snapshot, and uses the normal `user://build_save.json` path inside fresh isolated XDG roots. Existing saves cause an early refusal.

Measured sequence:

1. Twenty reward-eligible, non-demo normal roots die with the bag closed, through real damage settlement and ordinary reward handling. This must yield twenty normal XP calls, two equipment rewards, one jewel, and one final HUD/save flush.
2. First I key route opens the real bag. A direct call to production `main._process` while the bag is open must leave simulation state unchanged; no hits are claimed while paused.
3. The actual bag grid selects the eligible magic item. Three I close/reopen pairs measure unchanged warm opening.
4. The actual target selector chooses damage, the real targeted button requests one quote, and the real confirmation button executes one craft. Exactly sixteen shards must be debited and the saved snapshot must reload identically.

Per-phase data includes synchronous elapsed microseconds, real `changed` signals, real `refresh_generation`, and inclusive model/root instrumentation. Nested timings overlap and must never be added together. Metadata invocation counts bound dropdown work using the actual source chain `crafting_operations → set_operations_context → _refresh → _refresh_targeted`; the dropdown itself is not replaced or independently timed. Startup, inter-phase frame settlement and fixture work are excluded. Results do not establish deferred layout/render costs, large-inventory scaling, GPU costs, Windows FPS, or performance thresholds.

Reproduce only in a free CPU measurement window using the already imported production project. Set each XDG directory to a fresh child of a `/tmp/godot-m1-v050-*` directory, `INVENTORY_PROFILE_SOURCE` to the verified baseline SHA, and `INVENTORY_PROFILE_OUT` to an absolute result path. Run the approved Godot binary with `--headless --path . --script tools/diagnostics/inventory_reward_profile.gd`; do not invoke editor/import or a GUI. Preserve stdout/stderr next to the JSON and verify completion, no script errors, and zero exit status. This run used `/tmp/godot-m1-v050-inventory.yvp7xn/{data,config,cache}`; the actual save was `/tmp/godot-m1-v050-inventory.yvp7xn/data/godot-game-preview-v021/build_save.json`.

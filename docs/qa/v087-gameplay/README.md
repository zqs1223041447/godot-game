# v87 frost guard chill: bounded Main gameplay evidence

Executed once after the coordinated import: **174 checks, 0 failures**, exit0,
4.881 seconds, with no script or test errors. Original output and execution
receipt are in `../v087-integration/main-attempt01.log.txt` and
`main-attempt01-result.json`; tested hashes are in `main-attempt01-inputs.json`.

`tests/frost_guard_chill_gameplay_test.gd` uses the actual Main scene and the legal
`enter_town_test → craft_map → start_map` path. The primary map is unmodified
`ginkgo_arcade`, with its fixed wave 6 and 37 initial roots. Frost sources are
selected from that initial roster; the harness never injects a combat actor.

The source fixture follows the existing `mana_guard_gameplay_test.gd` approach:
a canonically valid level 3 earned-point budget, followed by seven real source
allocation transactions ending at node 34098. Its 40% mana diversion is derived
from the actual model. This is a legal fixture, not evidence that the character
naturally earned those points during this short run.

Positions, health/mana/shield, selected defense values, movement speed, actor
movement and attack clocks are controlled for exact consumer timing. The 100%
mana-only scenario is expressly an interface boundary, not a supported source
build. Map completion is a narrowly labeled completion-consumer fixture, not a
second full progression or rewards test. Screenshots are not a pass condition.

The harness covers original 0.9-second/radius-90/0.8-damage frost warnings,
unchanged Defense receipts, actual cold shield/mana/life loss, two real warning
hits refreshing a single status, movement integration across expiration, utility
movement/protection, malformed context atomicity, detached status getters,
source refund/equipment edits, and death/restart/town/completion cleanup. The
exploration checks cover the 37- and 25-root initial rosters, 450-unit plus LOS
wake, offscreen damage wake, dormant recovery/cooldowns, and camera behavior.

Run only after the parent has prepared the Godot import cache. Use a fresh
directory for every independent run, for example:

```sh
XDG_DATA_HOME=/tmp/godot-m1-v087-chill-main-UNIQUE \
FROST_CHILL_GAMEPLAY_OUTPUT=/absolute/path/to/gameplay-receipt.json \
godot --headless --path /absolute/path/to/project \
  --script res://tests/frost_guard_chill_gameplay_test.gd
```

The script fails closed with exit 78 outside the dedicated `/tmp` XDG prefix.
It stops dependent sections immediately after missing required fixture data.
The emitted JSON contains section counts, failed labels, entry identities,
source provenance, and the actual warning/Defense/chill receipts. The successful
first-run report is `main-result.json`. No historical full suite, second full-map
completion run, screenshot gate, Windows export, or long benchmark was added.

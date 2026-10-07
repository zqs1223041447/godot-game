# v101 Ginkgo inner-circle / outer-annulus runtime verification

Production authority: `MapBossProfiles.ginkgo_shelter_slam`, stable map attack ID. The existing self-at-start center and 240 trigger are retained. The action emits a 130-radius circle after 1.4 seconds, then a 130–240 annulus after an additional full 1.0 second. Each event uses a frozen copy of the original typed contact components multiplied by 0.6. Recovery starts only after the second event, with a 1.9-second base scaled by the existing `MonsterCatalog.telegraph_policy` attack-speed calculation. These are potential hit events; existing geometry, walls and immunity determine actual damage.

Ginkgo receipts use `profile_id=ginkgo_inner_outer`, `balance_version=original-ginkgo-inner-outer-v1`, and the unchanged telemetry schema version. The annulus is explicitly `annulus_attack` / `annulus`, with `inner_radius=130`. The visual snapshot reports the current shape and current radius/windup; its stage-local clock resets after the first event while the internal total clock remains continuous. Recovery snapshots begin at elapsed 1.0 for the second stage.

`tests/ginkgo_ring_runtime_test.gd` is the focused pure-data suite. It covers:

- Complete timing, frame partitions, huge delta, 100-source cap, no replay, stable event ordering and frame-local timestamps
- Freeze, partial frozen prefixes, liveness cancellation, explicit cancel/reset and new identities on restart
- Snapshot isolation for the center, stage definitions, profiles, typed packets and later source changes; no RNG consumption
- Rejection of missing/forged Ginkgo identity, altered stage budgets, malformed inputs and unauthorized recovery before allocating state or attack IDs
- Real player radius 15 plus arbitrary target radii, inner/outer inclusive tangency, safe center, large targets, invalid rings and finite extreme geometry
- Unfiltered byte-for-byte current trajectories against the frozen bdea0872 scheduler for Garden, Ruins, Sunwell and five ordinary templates, timed and untimed, including pause and error outputs; exact legacy circle results remain covered

The frozen source is derived from commit `bdea0872bc3542aa784cb616dfbf43fb4b1b984d`. `frozen/source-manifest.json` records original and frozen SHA-256 values. Only global class names are removed to prevent class collisions, and the frozen runtime's map-boss import is redirected to its frozen counterpart. Shared unchanged packet/catalog dependencies remain current-source; this differential establishes the scheduler/authority behavior of the scoped change, not equivalence of every game subsystem.

Run after the coordinated project import, with isolated Linux storage:

```sh
XDG_DATA_HOME=/tmp/godot-m1-v101-runtime/data XDG_CONFIG_HOME=/tmp/godot-m1-v101-runtime/config XDG_CACHE_HOME=/tmp/godot-m1-v101-runtime/cache /usr/local/bin/godot --headless --path . --script tests/ginkgo_ring_runtime_test.gd
```

Result: Godot 4.6.3 headless, 779 checks, 0 failures, exit 0. `runtime-first.log.txt` contains the complete first-run output without parse/runtime errors. The test was run once after the coordinated project import; there were no failing test attempts. `validation.json` pins the production and test hashes actually checked. Main settlement and renderer checks are separate and are not implied by this pure suite.

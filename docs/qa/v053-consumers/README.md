# v053 Fire DoT consumers

The focused consumer checks pass. Production changes are outside this test package.

## Results

- Pure consumers: **836 checks, 0 failures**, exit 0, 0.868 s. Run: `20261005T145710829605Z-results.json`.
- Actual main: **152 checks, 0 failures**, exit 0, 3.095 s. Run: `20261005T150309992354Z-results.json`.
- Zero-source, published-v052-main/current-main comparison: **120 ticks per side**, both exit 0, 3.111/2.812 s. Run: `20261005T150510561375Z-results.json`.
- Both simulations produced 3 accepted casts, 3 deaths, 28 projectile hits, at most 9 active burns, and 120 frames with burn damage. Read-only inspection of the retained observations found **1,226 distinct positive-width burn segments with positive settled health loss**, totaling 679.184999999996 health on each side.
- Every recorded simulation run retained exact before/after SHA-256 maps of source inputs; all source sets stayed stable during their run. No historical suite, endurance test, engine import, production edit, or git write was performed by this consumer work.

## Fixed oracle and limits

Published base: `0abadf05c94545fb7585f5a7565cd7a8930c26cd` (v0.52.0).

`oracle-manifest.json` records the original source hashes and every fixture transformation. `v052_main.gd` is an exact byte copy of published `scripts/main.gd`. The published Combat/Compiler/Burn fixtures only remove their global class names, and redirect the old compiler's Combat/Burn preloads to those fixed copies. The pure comparison therefore does not derive its old formula by stripping the new result.

The main comparison holds the current shared dependencies and save schema constant, and swaps only published/current main execution. It proves zero-passive consumer equivalence under the same current model; it does not claim that schema-31 saves and schema-32 saves are identical. The separate pure suite compares the complete published-v052 compiler and snapshot bytes for absent/numeric-zero sources.

Final exact comparison: `20261005T150510561375Z-legacy-comparison.json`.

- Observation stream: 19,017,000 bytes per side; SHA-256 `d684a04e11a14e03a5a7ccec308fffbcb19bc0ac54b2f8f1c67cece6da33e2a1`
- Final save: 12,178 bytes per side; SHA-256 `4fdcf94b6e5d466263ca5d21554eb2b5df89fdaef9057eb4c7d3030eb45cf20c`

Each tick records enemies, projectiles, pending monster spawns and roots, world RNG, complete model, health/mana/shield, combat/damage/incoming traces, group cooldowns, flask state, burn/shock statuses and burn trace, critical RNG checkpoint, leech, feedback, particles/floating text, save count, and saved bytes.

Observation streams are stored as `.bin.gz`. `observation-archives.json` contains compressed and raw hashes and confirms byte-for-byte decompression verification. Save files remain uncompressed. `legacy-observation-inspection.json` records counts read from the existing streams; this inspection did not run the game. Its retained log includes Fontconfig cache warnings from the read-only process, with exit 0 and successful Variant decoding.

## Coverage

Pure consumers cover complete absent/zero snapshot and compiled-result bytes for normal skills, basic attacks, Ignite and Ember; boolean, NaN, infinity, negative, string/container and explicit snapshot-zero rejection; overflow; additive 0.04 + 0.06 = 0.10; unchanged direct and secondary hits, costs, cooldown and duration; Meteor and Tornado parent/child previews; one critical factor; and unchanged full Shock compilation apart from the inert optional source key.

Actual-main checks exercise real Meteor casts and burn health loss, critical and noncritical Ignite/Ember, defense applied once, no tick RNG/critical/leech/model/save changes, one-hop Ember inheritance without reapplying the passive, original absolute expiry at 3 seconds, stronger/weaker/equal ownership, enemy telegraph burns, and Shock hit/status equivalence. Exact-equality arbitration includes a test snapshot with propagation removed while keeping the same burn policy, plus a direct runtime admission with exactly equal DPS; this avoids disguising near-equal floating-point values as equality.

The allocation fixture provides lawful level-three earned points and the existing Marauder prefix `47175 → 31628 → 9511 → 23881 → 26523 → 6446 → 10221`. Node `54396` is allocated and refunded through the real guarded model API. Both operations spend/refund one point and cause exactly one normal transaction save, with no new RNG draws. A genuinely owned Ignite support is equipped into the real Tornado group; the model cast, `Preview.burn_lines`, disk reload, active parent hit after refund, and naturally spawned child hit after refund all consume the frozen +4% source correctly.

## Preserved attempts

The first actual-main attempt (`20261005T150047074891Z-gameplay.log.txt`) had six failed byte comparisons. Numeric and gameplay assertions passed; the fixture reused MonsterRuntime/TelegraphRuntime objects whose reset intentionally preserves monotonically increasing identities. Fresh runtime objects corrected the A/B fixture without modifying or normalizing production provenance. The original log and exit/source metadata remain intact.

The first zero-source comparison (`20261005T150321367880Z-*`) was byte-identical and exercised deaths, but later inspection confirmed zero active burns and zero positive-width burn health-loss segments: its initial hit killed all 12 targets. The single probe fixture was strengthened with durable neighbors. The final comparison above exercises real burn application and settlement. The 836- and 152-check suites were not rerun for this fixture-only extension.

## Reproduction

After the normal project import is ready:

`python3 docs/qa/v053-consumers/run_consumers.py --suite all`

The runner invokes only the two new consumer scripts and the two modes of the same 120-tick legacy probe, gives every process a fresh `/tmp/godot-m1-v053-consumers-*` user directory, retains separate logs and source hashes, records exit codes, and stops on a failure. Individual modes are `consumer`, `gameplay`, or `legacy`. New probe runs emit raw `.bin` files; the checked-in observations were losslessly compressed after exact comparison and read-only inspection.

# v45 Ignite compiler and frozen-projectile evidence

Validated with Godot 4.6.3, using isolated `/tmp/v045-ignite-compile/{data,config,cache}` XDG directories. This focused check does not instantiate `main.gd`, import the editor, modify production sources, or write player saves.

## Result

- `ignite_compilation_test.gd`: **531 checks, 0 failures**
- Every compatible existing single support paired with Ignite: **11 pairs** across Meteor and Tornado
- Actual released-v44 compiler: **42 successful frozen casts**
- Current compiler, using the identical external probe: **42 exact record and whole-cast byte matches**, 0 failures
- All 34 entries in the before/after hash manifests match: combat sources, game data, weapon-local rules, the test and probe, and the retained released PCK

Logs: [focused test](ignite-compile-focused.log.txt), [released PCK probe](ignite-compile-v44.log.txt), [current probe comparison](ignite-compile-current.log.txt). Source manifests: [before](ignite-compile-source-before.json), [after](ignite-compile-source-after.json).

## Focused contracts

Admission covers the two valid and all eight invalid active skills, basic-attack rejection, duplicate Ignite, six-support rejection and the legacy two-slot limit. The added-fire fixture independently compiles for all ten skills; each of the six ineligible offensive skills demonstrably receives real fire in its assembled packet and still cannot equip Ignite or Fire Focus. Utility skills remain ineligible as well.

Meteor's direct role and Tornado's parent/child roles use the exact policy: duration 3 seconds, DPS 30% of post-primary-modifier fire before defense, primary hit multiplier 0.75, mana multiplier 1.20 and unchanged cooldown. All primary components receive the hit penalty once, including Tornado physical and fire. Independent secondary explosion damage remains unchanged. The noncritical preview excludes target resistance and agrees with the final composed primary hit. Zero-damage casts display zero DPS/total and cannot start a burn.

Every compatible existing single-support pairing and one five-support group per eligible skill compares full compiled bytes in both support orders. The five-support groups are:

- Meteor: Ignite, Fire Focus, Efficiency, Quickcast, Concentrate
- Tornado: Ignite, Fire Focus, Focus, Volley, Efficiency

Tests establish input purity and detached policy/preview/packet copies; reject any preexisting `burn_policy` on raw compiler input, including valid, empty and malformed examples; and reject recompilation of a compiled Ignite snapshot. Runtime policy-value validation, actual critical damage/burn settlement and gameplay tick behavior belong to the separate burn/main integration tests, not this report.

The projectile test launches five frozen Volley parents, splits to 15 children, then returns all 15. Original policy, exactly one Ignite modifier, and the already-frozen critical roll survive every stage and both outbound/return contact events. Source-stat and compiled-cast mutation after launch cannot affect the carried snapshot. Natural range/lifetime explosions erase only their own event snapshot's burn policy and keep the independent secondary packet; the carrier/source snapshot remains intact and cannot explode twice. Split, consumed hit, terrain collision, child-budget cancellation and run reset produce no natural explosion.

## Released-v44 oracle provenance and scope

`tools/ignite_v44_baseline_probe.gd` ran as an absolute external `--script` with `--main-pack /workspace/scratch/a51485f153de/v044-final-release/game.pck`. Its `res://` compiler, combat data and registry were loaded from the old pack; the probe confirms `source_has_ignite=false`. The same script then ran against the current project and confirms `source_has_ignite=true`. There is no current-code feature flag standing in for historical output.

The oracle stores raw input snapshots and complete `var_to_bytes(cast)` outputs. Comparison checks entire record bytes, including inputs and support order, and separately checks all current complete compiled output bytes against the old fixture in the focused test. Container file hashes differ because the provenance flag differs; all 42 actual cast outputs match exactly.

The 42 records deliberately cover a bounded representative set:

- All ten active skills with no supports, under both base and rich snapshots: 20
- Basic attack under both snapshots: 2
- Six historical pairs under both snapshots: 12
- Four historical five-support groups under both snapshots: 8

The rich fixture includes added damage, global/projectile/area/element/spell/type modifiers, critical profiles, attack leech, resource-cost modifiers, spatial modifiers, extra projectiles, return and independent-explosion grants. Historical pairs cover Tornado Focus/Volley, Meteor Breadth/Concentrate, Frost Heavy Projectiles/Lingering Chill, Chain Extension/Reach, Cleave Physical Focus/Concentrate and Shade Bolt Efficiency/Heavy Projectiles. Historical five-support groups cover Tornado, Meteor, Frost and Chain. This is not a rerun or claim of the historical exhaustive support matrix.

SHA-256:

- Released v44 PCK: `e0611f64aca665e4b2fe37d6bde54f56a3a633f0b7124f4ba9e98f2527d0fc0f`
- External probe: `ef9d3066fe57a3189b1a5d70fb73b64a69fd6da7c17f27f321bb56036e5561fa`
- Focused test: `ef78851ceabdc0afee3528717862a32084e8893fcaed2e360f5e0ad2c2c2292c`
- Released-v44 fixture: `7a60d4f4f45ca87ad7238ad28cf572c57a3c0510e02e46bd48b46c25f706de4d`
- Current fixture: `69f176d517cf2b55c1261896fdae5f5ce12853f97eb2e90f3d5fa594acf78238`

Exact commands and exit statuses are retained in the logs. The focused test can be rerun with isolated XDG directories and `godot --headless --path . --script res://tests/ignite_compilation_test.gd`; its committed v44 fixture supplies the historical oracle without needing the old pack at test time.

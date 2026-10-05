# v054 faster-burning consumers

Focused verification against published v053 `e3a5f7559ecbcb2cb56a9c192d75899fdcf43b3a` passes. This package contains tests and evidence only.

## Results

- Consumer suite: **1,050 checks, 0 failures**, exit 0, 0.979 seconds. Evidence: `20261005T161621555876Z-consumer.log.txt` and matching results JSON.
- Actual-main suite: **292 checks, 0 failures**, exit 0, 2.507 seconds. Evidence: `20261005T161652870732Z-gameplay.log.txt` and matching results JSON.
- Frozen-v53-main/current-main comparison: **120 ticks on each side**, exit 0, 3.165/2.890 seconds. Complete observation bytes and final save bytes match. Evidence: `20261005T161655427331Z-legacy-comparison.json`.
- Both legacy simulations produced 3 accepted casts, 3 rewarded deaths, 28 projectile hits, up to 9 active burns, and 120 frames containing burn damage. The recorded streams contain **1,226 distinct positive-width segments with positive actual health loss**, totaling **452.789999999991** health per side. These are asserted during the probe; this fixture did not use the earlier all-targets-die-on-first-hit pattern.
- Every attempt preserves process exit, log, timing, isolated user directory, and before/after input SHA-256 maps. Every run had stable input hashes. No production edits, engine imports, git writes, historical full-suite run, or endurance test were performed by this package.

## Fixed oracle and exact comparison

`oracle-manifest.json` records source hashes and each fixture transformation. `v053_main.gd` is an exact byte copy of the published main. Pure fixtures remove their global class names; published Combat's Burn preload and published Compiler's Combat/Burn preloads point to the frozen copies. There is no formula derived by subtracting or stripping the new compiler result.

The legacy main comparison keeps current shared dependencies and schema 33 fixed and swaps only the published/current main script. It proves zero-speed main consumer equivalence under the same current model, not equality of schema-32 and schema-33 saves. Complete absent/numeric-zero snapshot and compiler bytes are independently compared with the frozen published-v53 sources, including nonzero existing Fire DoT multipliers.

The exact 120-tick stream records enemies, projectiles, monster spawn queues and roots, RNG, complete model, resources, combat/damage/incoming traces, group cooldowns, flask state, burns/shocks and burn traces, critical RNG, leech, feedback, particles/text, save counts, and saved bytes.

- Observation stream: **18,954,404 bytes** each; SHA-256 `48f2809b81f475c392b53ba6b782b1b666626e775a71ae0b0c2358f2de7b5d9f`
- Final save: **12,178 bytes** each; SHA-256 `a42172b93712ea261276d3dd802aac581c93e260f61773e2c8b6fe5ebe2ecbc0`

Observation streams are retained as `.bin.gz`; `observation-archives.json` records raw/compressed hashes and verified byte-exact decompression. Saves remain uncompressed.

## Coverage

The pure suite checks 880 complete published-v53 compatibility assertions for absent/numeric-zero speed, basic attacks, all normal skills, Meteor/Tornado Ignite and Ember, and legacy Burn API results. Malformed source/snapshot values and overflow fail closed. The combined fixture separately sums Fire DoT `0.04 + 0.06` and speed `0.05 + 0.05 + 0.15`, proves `(old fire × rate × (1 + M)) × (1 + F)` DPS and `3 / (1 + F)` duration, and checks unchanged theoretical total with the explicit tolerance **max(1e-9, 1e-12 × abs(base_total))**. It checks final total equals final DPS times final duration, frozen critical factors, unchanged direct/secondary hits, costs, cooldown, movement, and full Shock compile after removing only the inert speed key.

Actual-main coverage includes:

- Real Meteor Ignite/Ember, critical and noncritical hits, frozen Fire DoT plus speed, actual half-second burn health loss with resistance once, and unchanged hit/RNG/save traces
- Guarded source allocation/refund of `11364` through the model, one normal save per transaction, exact point accounting and disk reload; both genuinely owned Ignite and Ember supports equip into Tornado groups
- Active Tornado parent hits after refund, natural splitting into children, and child hits after refund. All carriers retain their original snapshot, +5% DPS factor, and compressed lifetime
- Early DOT death at the exact compressed time, precise post-death recipient damage, original compressed expiry, later stat changes neither rescale nor extend active burns, exact-expiry disappearance, no later repayment, and one-hop spent-transfer termination
- Stronger/weaker/exact-equal arbitration driven by actual DPS even when theoretical total orders the candidates oppositely; incoming exact-equal duration and provenance win
- Simultaneous source deaths settle before candidate selection; deterministic source-ID ownership, nearest-eight cap, no replacement candidate when a stronger existing burn rejects transfer, no double speed multiplication, and byte-identical winners after reversed actor traversal
- Actual terrain line of sight and spawn protection; unchanged real enemy telegraph burn and Shock status/hit traces

The legal allocation fixture uses class 4, level 8 and the source prefix `50986 → 39725 → 63649 → 49806 → 6580 → 19711 → 20010 → 23471 → 5237 → 6363 → 29937 → 8544`, with 11 spent and one unspent point. Node `11364` contributes exactly +5%. Fresh MonsterRuntime and TelegraphRuntime objects are used for A/B fixtures so their monotonic actor/attack identities remain semantically correct and comparable.

## Preserved fixture corrections

The first pure attempt (`20261005T161554685509Z-*`) reported three failed Shock whole-result comparisons. The frozen v53 Combat fixture still pointed to current BurnRules and therefore accidentally carried the new speed key in the supposed old snapshot. Redirecting that preload to the frozen v53 BurnRules corrected the oracle; the resulting 1,050-check pass uses an independent old source path.

The first gameplay attempt (`20261005T161621555876Z-gameplay.log.txt`) reported only two presentation assertion failures because the test expected `+5%` while the authored speed line says `燃烧结算加快 5%`. The fixture expectation was corrected; all 292 checks pass. No production change was needed. Every failed attempt and its input hashes remains retained.

## Reproduction

After normal project import has completed:

`python3 docs/qa/v054-consumers/run_consumers.py --suite all`

Individual modes: `consumer`, `gameplay`, or `legacy`. The runner invokes only the two focused scripts and the old/new modes of the 120-tick probe, uses separate `/tmp/godot-m1-v054-consumers-*` directories, preserves every attempt, and stops an individual sequence on failure. New legacy runs emit uncompressed `.bin` files before optional lossless archival.

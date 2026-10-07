# v101 Ginkgo inner circle → annulus: actual Main evidence

The first focused run passed **453 checks, 0 failures, 16 groups**, Godot exit **0**, in **5.353 seconds**. `first/stderr.log` is empty. There was no failed attempt and no Main rerun. No production/Main/UI files were changed by this fixture.

This is controlled headless integration evidence, not natural-combat footage, a full four-map campaign, a performance benchmark, or Windows acceptance. It loads the actual `main.tscn` and starts a fresh formal character using the current canonical rules. Map entry uses the real draft and start transactions. The schema is read from `Rules.VERSION`; it is 53 in this run. The player's body radius is read from `Main.PLAYER_RADIUS`; it is 15.

## What passed

- Both formal entries contain all 36 ordinary roots plus the original boss immediately. All 37 actor IDs, root IDs, spawn keys, authored positions and standard reward routes agree with actual spawn records. Entry consumes no gameplay RNG. The boss remains at authored relative coordinate `(3180,320)`, actual world coordinate `(3222,424)` in the arena whose origin is `(42,104)`
- Natural birth protection expires through Main ticks. The actual boss wakes through proximity/LOS and locks its own start position through the real admission path. Admission consumes no gameplay RNG
- Held `move_down` input reaches distance 180 in 20 actual ticks, age 0.333333. The first circle resolves safely at age 1.4. Held `move_up` input returns to distance 100 in 20 actual ticks, age 1.733333, before the annulus resolves safely at age 2.4. Neither hit is applied
- Remaining at distance 180 applies only the annulus hit. Distance 256 avoids both. At distance 115, the body touches the inner boundary and both events hit. Distance 114.99 takes the circle but is fully safe inside the annulus. Distance 255 touches the outer boundary and takes the annulus
- Both packets use the original boss contact-component authority at 0.6 each. Existing defense spends the 5-point probe shield before health, with exact predicted values. The natural tierI boss contact damage is 28.564; one nominal packet is 17.1384, and two are 34.2768 before the existing settlement rules
- One real 2.8-second Main tick crosses both events at within-tick times 1.4 and 2.4. With no initial immunity, both apply. With 1.5 seconds of immunity, only the second applies. With 2.5 seconds, neither applies. Further recovery ticks never repeat an event
- Real source knockback and held player movement preserve the locked center and frozen packet. Both emitted events retain the original source, attack identity and center
- Separate controlled freeze probes attach the existing valid 0.2-second boss freeze at local ages 0.5, 1.6 and 2.6, covering first windup, second windup and final recovery. A 0.3-second Main tick advances only the thawed 0.1-second suffix. Phase/identity/center are retained; full completion is delayed by exactly 0.2 seconds, without reset or repeated hits
- A clearly labelled controlled wall probe relocates the admitted boss beside an existing planter corner, obtains a real attack lock, and places the player at a legal annulus-overlap point behind that planter. Actual terrain LOS blocks settlement. This does not claim a shelter exists within attack range of the natural boss birth
- Returning during the outer warning clears the pending sequence, actors, queue and spawn metadata. Death before the first event cancels both events, awards one root reward and queues the original four children. Actual spawned children retain the boss spawn key, have no root reward or boss policy, and add no root progression when killed. Repeated boss death consumes no RNG or reward. The remaining ordinary roots still prevent map completion

The actual tierI boss recovery is 1.8479299537288065 seconds, using the unchanged `1.9 × BASE_ATTACK_SPEED / current_attack_speed` formula. Nominal full action duration is therefore 4.2479299537288065 seconds. Timings and packet/shape authority come from actual frozen runtime snapshots and Main events.

## Fixture controls and scope

The fresh character receives no equipment, currency or progression grant. Initial map geometry and source records are preserved. After entry, surrounding resident actors are made stationary and given long attack timers so the targeted boss probes remain bounded. Individual probes explicitly reset runtime resources/status, position the player at legal points, and prevent a fresh boss action after the tested recovery. The wall case explicitly relocates the admitted boss. Freeze is attached through the existing status runtime with controlled provenance; it is not presented as a player-owned Frost Lock cast. Deaths use the actual defense settlement and Main death/reward path.

The held leave/reenter route uses actual input actions and Main movement ticks. Direct position assignments in boundary and wall probes are only setup controls and are not movement acceptance evidence.

Other three boss output compatibility is covered by the separate pure-runtime worker. This focused Main test does not rerun their campaigns or claim new full-release coverage.

## Artifacts

- `first/main-result.json`: full actual boss/policy/initial roster snapshots, both phase events and damage settlements, input movement samples, freeze states, wall geometry, and lineage metadata. Vectors are numeric `[x,y]` arrays; rectangles contain `position` and `size`
- `first/formal-initial-save.json`: exact canonical `state.snapshot()` data from the first fresh isolated formal map entry, retained for read-only documentation reuse. This is QA fixture data, not a real user's profile
- `first/test-source.gd.txt`: exact test source used for the successful run
- `first/telegraphed-area-runtime-tested.gd.txt`: exact tested runtime source, reconstructed by removing the single subsequent zero-inner-radius guard and verified against the pre-run SHA-256
- `first/run.json`: exact tested input SHA-256 hashes, command, base commit, isolated XDG root, duration and exit code
- `first/stdout.log`, `first/stderr.log`, `first/exit-code.txt`: unmodified execution evidence
- `tested-inputs.json`: concise result and fixture identity, with post-run production-source difference disclosed

The successful Main run tested telegraph-runtime SHA-256 `85f653485d3da1392591fc9f3081628fe9dac8aa689ff08804cf7b8d1bed5512`. Immediately afterward, the runtime worker tightened the invalid-annulus guard so `inner_radius=0` rejects. The resulting SHA-256 is `e846533c6f6cd1c9e5c4726a17c0ebfddaae69add0ac8e22a361fbc6a1f773cb`. The valid `inner_radius=130` path exercised here is unchanged. No Main rerun was performed for that invalid-input-only correction; the coordinator confirmed 779 passing pure-runtime checks on the final source, including zero, negative and 130 boundaries. The archived tested runtime hash exactly matches the pre-run manifest.

## Reproduction

After the coordinator's single shared import, create fresh data/config/cache directories under a new `/tmp/godot-m1-v101-*` root. Set `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME` to those directories and `GINKGO_RING_MAIN_OUTPUT` to an existing writable evidence directory. Then run:

```sh
/usr/local/bin/godot --headless --path . --script tests/ginkgo_ring_main_test.gd
```

The recorded execution used an external 60-second timeout and Godot 4.6.3. The fixture refuses an existing `user://build_save.json`. Optional `GINKGO_RING_MAIN_GROUP` values `routes`, `timing`, `wall`, or `lifecycle` restrict an affected-group rerun; unset runs all groups. No new import is required after the shared import.

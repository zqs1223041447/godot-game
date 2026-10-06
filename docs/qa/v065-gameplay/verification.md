# v065 Zealot's Oath: actual gameplay consumers

Final focused run: **170 checks, 0 failures**, Godot 4.6.3 exit 0 in 2.988 seconds. `gameplay-03.log.txt` has no script or engine errors. `gameplay-03-run.json` records the isolated userdata path, command, and SHA-256 of the harness and four production inputs; `gameplay-03.json` contains the actual projected stats and burn comparison.

The harness instantiates the real main scene and canonical model. It resolves pending recovery, admits existing legal gear, and equips it before loading the lawful schema-41 level-19 Marauder fixture through the actual store. Its 23 earned points are allocated through actual connected-source transactions. Gear vocabulary remains 39. The only fixture setup changes are earned level/budget/class; no production hooks or mechanism-stat overrides are used.

## Verified behavior

- The supported branch supplies 10 flat life regeneration plus 1.8% per second; final life is 222 and final ES is 120.96, including the existing guardian robe, legal lanternveil charm, the 4% maximum-ES source, and Intelligence
- Inactive life regeneration is 13.996/s with no new regeneration stats keys. Active life regeneration is zero and ES regeneration is 12.17728/s, exactly `10 + 0.018 * 120.96`. Existing recharge stays 16/s with a four-second delay
- During a half-second tick with an ongoing actual player burn and recharge still delayed, life rises only without the keystone; ES gains converted regeneration with the keystone. The burn deals the same 9.5 damage and resets the existing recharge wait in both cases
- Continuous ES regeneration and recharge add independently. Crossing a recharge threshold grants a full tick of regeneration and only the post-threshold portion of recharge. Maximum ES clamps recovery, and surplus never heals life
- The actual flask, existing equipped life-leech affix and actual attack-hit consumer, and pickup all continue recovering life. They add no converted ES recovery
- Actual paused and dead `_process` entry points leave resource/recovery state unchanged; regeneration does not revive a dead player
- Real allocation/refund/equipment transactions preserve current resource pools and recharge waits. Failed-save allocation, refund and equipment commands preserve exact model/disk/cache/runtime state, successful-save count, and signals, with one failed save attempt each. Failed allocation/refund consume no global RNG; recovery and transaction checks also retain the main RNG and critical state
- Legal body-armour replacement changes percentage regeneration using the new final ES while changing its separate old recharge contribution by the expected amount. Actual C-panel/profile reads remain read-only
- Refunding both actual regeneration source nodes while keeping the keystone leaves zero regeneration; refunding the keystone removes the active-only keys. Save/reload reproduces the active allocation and final profile

## Scope and attempts

This is a bounded actual-main/model test, not a full historical simulation, screenshot pass, Windows run, or balance claim. The separate presentation-mock test and legacy 90-tick comparison were outside this worker's scope and were not rerun.

Attempt 01 stopped on a harness-only inferred-type parse error. Attempt 02 timed out because cleanup after the actual-death check tried to close the existing latched death menu without a HUD refresh. Cleanup now invokes the existing HUD refresh and uses bounded closing; no production change was needed. Both earlier attempt records are retained. Only attempt 03 is the final passing evidence.

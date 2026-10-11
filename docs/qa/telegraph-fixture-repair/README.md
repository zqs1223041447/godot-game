# Ember telegraph assertion repair

2026-10-11 · Godot 4.6.3 headless · production HEAD `074322438d4e1f9f373e06b8deafe44acc4d61a9`

Only the catalog-source assertions in `tests/telegraphed_area_test.gd` changed. No production, timing, radius, damage, tolerance or existing scenario was changed.

## Why the assertion was stale

The earliest available repository commit, root `fd072824d10def4b39402a5934b68de92b3303d1`, already contains all four pieces:

- `scripts/combat/burn_rules.gd`: enemy policy duration 3, rate fraction 1/3, upfront fire multiplier 0.50
- `scripts/combat/telegraphed_area_runtime.gd`: scale contact components by the area multiplier, then halve only ordinary ember_guard fire and attach the burn policy
- `tests/burn_rules_runtime_test.gd`: literal policy equality and an explicit assertion that already-halved enemy fire is not halved again by burn calculation
- The inconsistent generic telegraph assertion that every component, including ember fire, equals contact × 1.4

The only later runtime commit, `c7d5cc967c9a9ec42872bc3e500207544a675b53`, adds the boolean `has_state` query without changing damage. Current catalog policy and descriptive text likewise specify half fire upfront, half over three seconds. Current Main passes the emitted fire component into the burn rules after an applied hit. These source/history checks establish an existing authored split rather than inferring a new expected value from observed output. History before the imported root is unavailable here.

## Assertion changes and results

Ordinary sources retain contact × 1.4. Ember physical retains contact × 1.4; only ember fire expects contact × 1.4 × 0.5. Added checks lock the complete literal enemy/event burn policy and independently derive wave-3 rare brute damage from `(18 + 2 × 0.7) × 1.2 = 23.28`, with equal physical/fire contact weights. Thus immediate physical is 16.296 and immediate fire is 8.148. Neither independent expected value comes from emitted output or the runtime policy value. Crawler and brute must not acquire burn metadata. Existing generic mixed-fire fixture still requires full 14 physical + 14 fire, protecting against global fire halving.

- Before: 882 assertion executions, 1 failure, exit 1; only `ember_guard/fire` failed
- After: 889 assertion executions, 0 failures, exit 0; no SCRIPT ERROR / ERROR / FAIL lines
- The seven extra checks are five ember fixed-contract/formula checks plus two non-ember metadata checks. All original assertions still execute; counts include loop executions, not independent scenarios.
- `git diff --check`: pass

Raw logs: `before.log`, `after.log`. This was a bounded focused runtime test, including its existing 100-cycle capacity loop. No full suite, GUI, export, network or commit was performed. It does not newly verify Main/player application, burn tick settlement, map-boss overrides or natural gameplay; those production paths were read for context, not run or changed.

## Reproduce with isolated saves and strict failure status

From the repository root:

```sh
(
  isolated=$(mktemp -d /tmp/godot-m1-telegraph.XXXXXX) || exit 1
  status=0
  XDG_DATA_HOME="$isolated/data" XDG_CONFIG_HOME="$isolated/config" \
  XDG_CACHE_HOME="$isolated/cache" timeout 90 godot --headless --path . \
    --script res://tests/telegraphed_area_test.gd > "$isolated/run.log" 2>&1 || status=$?
  cat "$isolated/run.log" || exit 1
  [ "$status" -eq 0 ] || exit "$status"
  scan_status=0
  grep -nE 'SCRIPT ERROR:|ERROR:|FAIL:' "$isolated/run.log" || scan_status=$?
  [ "$scan_status" -eq 1 ] || exit 1
)
```

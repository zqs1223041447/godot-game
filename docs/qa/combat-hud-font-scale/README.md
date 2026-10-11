# Persistent combat HUD font scaling

2026-10-11. Published baseline: `7a984ceac427527629dd083b775670fc7bce20b9`.

Thirteen additive HUD lines apply the existing authored-base font scaling to RunStatus, PlayerVitals, Hotbar and CombatHelp, including hidden help. Rebuilt hotbars inherit the current preference. A status resize handler keeps WorldControls at least ten local pixels below the status text while preserving its default y=130. No combat, bindings, materials or exploration drawing changes.

## Focused evidence

- Independent focused test: 2,944 checks, zero failures. Covers all three UI and font choices, repeated 100→120→100 round trips, refresh/reopen, saved settings reload, hidden help, rebuilt hotbars, text containment, target separation and unchanged build/bindings/world/RNG
- Cleanup hint test: 27 checks, zero failures
- Five largest-combination skill buttons received viewport mouse dispatch at their centers. This verifies viewport routing, not operating-system clicks or successful skill casts
- Existing canonical HUD integration retains the same baseline F1 assertion failure: 2,418 checks, one failure. It is not counted as passing
- Diff whitespace check passed

Native controlled Main captures used formal Ginkgo II, existing progression transactions, held simulation and disabled autofire. Linux Godot 4.6.3, X11/OpenGL Compatibility, Mesa llvmpipe; rendered sizes 1280×720 and actual 2560×1440 with a 1280×720 logical viewport. Default persistent-HUD and WorldControls crops were unchanged; maximum UI/font combination showed no new primary-text or skill-target overlap. Default HUD-root crops were byte-identical in eight comparisons. Random world actors were excluded from pixel comparisons. This is controlled graphics evidence, not natural combat, Windows DPI or performance evidence. Large screenshots and experiment copies are retained separately.

## Reproduce the focused check

Run from the repository root with disposable data:

```sh
(
  isolated=$(mktemp -d /tmp/godot-m1-hud-font-check.XXXXXX) || exit 1
  status=0
  XDG_DATA_HOME="$isolated/data" XDG_CONFIG_HOME="$isolated/config" \
  XDG_CACHE_HOME="$isolated/cache" timeout 75 godot --headless --path . \
    --script res://tests/combat_hud_font_scale_test.gd > "$isolated/run.log" 2>&1 || status=$?
  cat "$isolated/run.log" || exit 1
  [ "$status" -eq 0 ] || exit "$status"
  scan_status=0
  grep -nE 'SCRIPT ERROR:|ERROR:|FAIL' "$isolated/run.log" || scan_status=$?
  [ "$scan_status" -eq 1 ] || exit 1
)
```

No full-suite, CI, Windows or sustained-FPS pass is claimed.

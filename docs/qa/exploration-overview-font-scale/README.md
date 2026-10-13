# Exploration overview font scaling recovery

2026-10-13. Reimplemented locally from published baseline `0373f7`; this is not recovered unpublished work.

## Change

- The custom-drawn overview now uses the existing font preference for its authored 12, 13 and 20 pixel text
- HUD presentation updates the overview even while hidden, so reopening uses the current preference without another setting change
- At 100%, authored font sizes and text positions remain unchanged. Larger fonts use font metrics to keep footer rows apart, grow legend spacing, retain the close hint's right margin, and contain map labels at the edges
- Map fitting/projection, obstacle and marker drawing, world state and gameplay remain unchanged

## Focused checks

Linux Godot 4.6.3, headless, isolated temporary XDG data/config/cache, each invocation bounded by `timeout 90`:

| Check | Result |
| --- | --- |
| New dedicated test before implementation | 1 check / 1 failure: missing preference support |
| New dedicated test after implementation | 107 checks / 0 failures |
| Existing combat HUD font scaling | 2,944 checks / 0 failures |
| Existing cleanup hint HUD | 27 checks / 0 failures |
| Existing exploration overview, corrected schema invariant | 144 checks / 0 failures |

The dedicated test covers 100/110/120%, round trips, actual theme font metrics, edge label containment, footer separation, unchanged map projection, hidden-setting synchronization, reopening, visible refresh, and unchanged build/player/RNG. The existing overview test covers five formal map entries, physical key dispatch, lifecycle, retained live state and read-only observations. Its total varies with generated descendant combat cases.

The old overview test's hard-coded schema59 assertion failed on an isolated `git archive HEAD` baseline too (147 checks / 1 failure), as well as before the test correction in the working tree (154 / 1). It now records the initial canonical schema and verifies that it stays unchanged; it does not replace the stale constant with another version number. This changes only the test, not saves or migrations.

No native screenshots, rendered-pixel equivalence, natural gameplay, Windows DPI, performance or full-suite pass is claimed. Headless font metrics are layout evidence, not native visual acceptance.

## Reproduce

From the project root:

```sh
isolated=$(mktemp -d /tmp/godot-overview-font-check.XXXXXX)
mkdir -p "$isolated"/{data,config,cache}
XDG_DATA_HOME="$isolated/data" XDG_CONFIG_HOME="$isolated/config" \
XDG_CACHE_HOME="$isolated/cache" timeout 90 godot --headless --path . \
  --script res://tests/exploration_overview_font_scale_test.gd
```

The combat HUD test requires an isolated directory starting with `/tmp/godot-m1-`; the existing overview test requires `/tmp/godot-map-overview-` and an existing `OVERVIEW_OUTPUT` directory.

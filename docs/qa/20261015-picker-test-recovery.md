# Owned-gem picker input harness recovery — 2026-10-15

## Scope and diagnosis

Only `tests/owned_gem_picker_test.gd` changes. No production input routing, purchase, inventory, persistence, or schema behavior changes.

In the script-driven headless run, the root Window was 64×64. The first requested support slot had global rectangle `(76, 668.9, 38.72, 38.72)` and its parent scroll container occupied `(15, 75.9, 396, 631)`. The injected mouse position therefore fell outside the root viewport; `gui_get_hovered_control()` remained null. The picker never opened, and unguarded accesses to its entries eventually interrupted the coroutine instead of producing a clean test exit.

The harness now explicitly uses the project-sized 1280×720 root window and embeds popup windows only on the headless backend. Empty-slot clicks, occupied-slot clicks, right-click returns, popup Enter confirmation, Escape, and the final physical V cast still travel through `Input.parse_input_event`; they have not been replaced with direct production handlers. Existing direct signal calls remain limited to repeated/stale/canceled-selection negative cases, and the existing drop-validator/drop-method check is unchanged.

The obsolete fixed schema expectation of 59 is now an initial-versus-final version comparison, testing the stated invariant that picker actions do not migrate the schema. Missing purchased fixtures, unsuccessful picker opening, missing main selection, and empty stale/closing choice lists terminate through the JSON report path. Empty-state menu item reads check item counts first.

## Verification

Engine: Godot 4.6.3 stable, Linux headless. No graphical display or X11 socket was available; no graphical/native-popup visual acceptance is claimed.

Run from repository root:

```sh
D=$(mktemp -d /tmp/godot-owned-gem-picker-final.XXXX)
XDG_DATA_HOME="$D" XDG_CACHE_HOME="$D/cache" \
  GEM_PICKER_REPORT="$D/report.json" \
  timeout 90 godot --headless --path . --script tests/owned_gem_picker_test.gd
```

- Positive run: exit 0; 39 checks, 0 failures; all five paid canonical gem instances tracked by UID
- Local evidence: `/tmp/godot-owned-gem-picker-final.v4ZJ/log` and `report.json`
- Fault-injection verification: temporarily restored root size to 64×64, then restored the fixed source. Exit 1 with 9 checks and the expected single “Click actual empty slot opens owned-gem choices” failure; a JSON report was written. No out-of-range exception or timeout
- Negative evidence: `/tmp/godot-owned-gem-picker-negative.MWbY/log` and `report.json`

The fixture provides canonical physical currency and buys five gems through paid transactions. This test does not establish natural currency acquisition, visual rendering quality, native OS popup behavior, or Windows performance.

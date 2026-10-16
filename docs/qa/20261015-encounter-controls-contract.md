# Encounter controls preview and scroll contract, 2026-10-15

## Scope and diagnosis

The isolated component fixture still expected neutral health/speed multipliers and the old abbreviated speed label for every selection. The current component intentionally displays only selected canonical descriptions. Its six-option catalog also exceeds the old two-option `<500px` height cap when descriptions wrap. Those obsolete assertions produced nine failures; neither requires changing `scripts/ui/encounter_controls.gd`.

This change updates only `tests/encounter_controls_test.gd` and this verification record. The separate pause-panel keyboard focus-follow defect and its integration acceptance are outside this fixture's scope.

## Preserved and expanded acceptance

- Expected preview is assembled independently from the ordinary/selected heading and the compiler's ordered canonical definition descriptions. The test does not call the component's summary helper.
- Empty selection, all six singles and all 30 ordered distinct pairs are covered, including both input orders of armour/shield and health/shield. Exact text equality rejects missing, extra, stale or reordered description lines.
- Explicit checks preserve flat armour `+80`, shield based on unmodified maximum health, and shield's independence from the health modifier's order. Aggregate multiplier formatting cannot replace these meaningful units.
- Existing invalid-input, fail-closed status, detached input/output, read-only input, repeated confirmation, owner-lock, real mouse, keyboard-repeat and in-flight context replacement cases remain.
- Existing build snapshot, existing isolated save bytes, catalog and global RNG invariance guards remain.
- A real `ScrollContainer` replaces the unbounded VBox host. At 220/280 logical pixels and every supported font scale (100/110/120%), a 480px-high scroll viewport must reveal every option, description, heading, integration/risk label, preview, visible status and confirm button. Ordinary, single, ordinary pair, armour/shield, health/shield, owner-locked and invalid contexts are exercised.
- Existing recursive child bounds and wrapped-line visibility checks remain. Overflow must produce a vertical scrollbar. Reveal checks account for at most one pixel of integer-scroll/fractional-layout rounding and verify both host and actual logical viewport bounds. The vertical scrollbar’s width is excluded from the visible content rectangle.
- The fixture explicitly sets and verifies a 720×720 logical viewport. Physical window resolution or a 2K display is not used as evidence of logical layout capacity.
- Real mouse helpers scroll the target into view before dispatching input. A 70-second in-process watchdog fails a suspended coroutine; the external command is bounded to 90 seconds.

## Verification

Godot version: `4.6.3.stable.official.7d41c59c4`

Run from the repository root, without editor imports and using fresh isolated user storage:

```sh
D=$(mktemp -d /tmp/godot-encounter-contract-XXXX)
XDG_DATA_HOME="$D/data" XDG_CONFIG_HOME="$D/config" XDG_CACHE_HOME="$D/cache" \
  timeout 90 godot --headless --path . \
  --script res://tests/encounter_controls_test.gd
```

Result: exit 0, `Encounter controls: 3918 checks, 0 failures`.

This is structural/headless and input-routing acceptance, not a claim of a rendered screenshot review or proof of the separate HUD focus fix.

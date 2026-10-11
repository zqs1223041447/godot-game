# Canonical menu retention fixture restoration

## Scope

Local dot-only repair of `tests/canonical_menu_retention_test.gd`. Read the project `AGENTS.md` and prior `docs/qa/inventory-page-selection/README.md` before changing the fixture. No production code, cloud task, network access, commit/push, or full-suite run was used for this repair.

## Reproduced old failure

One fresh isolated run of the unchanged fixture with Godot 4.6.3 reproduced the prior failure exactly (`before.txt`):

- Four failed assertions: accepted cast after closing menus; compiled mana/cooldown charge; initial projectile count; live HUD mana/cooldown
- Then a null `pressed` access at the removed inventory `CharacterStats` control (old line 163)
- The script could not reach its summary/exit; the external 20-second timeout terminated it with exit 124

Current Main starts in formal town, and `cast_group` deliberately rejects combat there. The inventory header no longer builds the old character button; `GameHUD.handle_menu_key(KEY_C, true, false)` is the current character-sheet route. These were stale fixture assumptions, not a production regression from the inventory pagination change.

## Exact fixture adaptation

1. Keep loading the real `scenes/main.tscn`, disabling autonomous Main/HUD processing as before, and using a fresh isolated save directory
2. Assert the initial formal-town context and its correct cast rejection
3. Enter normal practice with the existing revision-checked `leave_normal_town(world_context().revision)` API, assert success and actual `normal` context, and fail finitely if entry fails; do not assign the world mode directly or replace the model
4. Take the original retention snapshot after that legitimate world transition
5. Also assert a real cast is blocked while the docks are open in practice
6. Replace both removed `CharacterStats.pressed` uses with the existing C shortcut route; keep the character sheet, derived-stat, level, visibility, refresh-generation, and overlay restoration assertions

All original behavior assertions remain, including node/generation retention, exact ownership snapshots, shared bag UID display, stale-binding rejection, craft cancellation, accepted cast with compiled mana/cooldown/projectile recipe, cached compilation reuse, hidden-view dirty/refresh behavior, and Escape priority. The character reopening assertion's label now names C instead of the removed button. No skips or relaxed expected values were added.

## Finite before/after gate

Exactly two engine invocations for this task: one before, one after. Both use a separate fresh `/tmp/godot-m4-menu-retention-*` directory so the fixture's existing isolation guard accepts the run. The before cap was 20 seconds; the after cap was 45 seconds.

```sh
phase=before  # then after, following the fixture edit
limit=20      # 45 for after
isolation=$(mktemp -d /tmp/godot-m4-menu-retention-$phase-XXXX)
mkdir -p "$isolation"/{data,config,cache}
XDG_DATA_HOME="$isolation/data" XDG_CONFIG_HOME="$isolation/config" \
  XDG_CACHE_HOME="$isolation/cache" timeout "$limit" godot --headless --path . \
  --script res://tests/canonical_menu_retention_test.gd \
  > "docs/qa/menu-retention-fixture/$phase.txt" 2>&1
status=$?
printf '\nExit status: %s\n' "$status" >> "docs/qa/menu-retention-fixture/$phase.txt"
```

After: **70 checks, 0 failures, exit 0** (`after.txt`). The existing character layout probe also runs again (656 px panel height; visible strength value 20). `git diff --check` passes.

This is a headless controller regression using actual Main, model and menu routes. It is not a claim of native-window pointer interaction, Windows testing, or full-suite coverage. The earlier pagination report remains historical; this report resolves its separately identified stale retention-gate limitation.

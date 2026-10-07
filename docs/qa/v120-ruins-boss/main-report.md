# Actual Main integration: ruins garden boss

Result: **341 checks passed, zero failures, 13 focused groups** on Godot 4.6.3. The final `main-run.log` is clean. `main-result.json` contains exact entry identities, native contour geometry, attack snapshots, movement endpoints/times, damage traces and cancellation evidence. `main-formal-initial-save.json` is a newly created lawful schema54 character, not an older fixture or migrated snapshot.

## Verified behavior

- Formal `await arena.open_map(...)` enters native `ruins_garden` with the strict map/collision ID and all 25 resident roots. Original root identities, spawn records, reward routes, allocation budget, authored boss birth and gameplay RNG are preserved
- The actual admitted boss resolves `ruins_garden_slam`, name `庭园缠印`, `player_at_start`, trigger420. Main rejects distance420.01 and admits distance420
- Center is exactly the player position at admission, explicitly different from the boss position. Held movement never changes it. The first radius90 circle waits the full1.15s; the second90–210 annulus waits another full1.0s. Exactly two events share the same attack/source/center, each at0.65 of contact components
- Real held `move_down` input leaves the circle in0.625s; held `move_up` returns to the locked center by1.775s. Neither settlement applies damage. This route uses ordinary Main movement, stats and native collision, with no teleport during the route
- Remaining at the center takes only the circle hit. Remaining in the outer band takes only the annulus hit. Inner and outer body tangencies hit;0.01-unit clearance is safe as specified. Applied damage is checked against the existing shared defense calculation
- Existing invulnerability expires between pulse deadlines correctly. One bounded outer-warning freeze pauses only its frozen interval and extends recovery exactly. Recovery retains the base1.9 attack-speed formula and emits no duplicate pulses
- Original prepared native polygons provide the wall test: a legal source and center start with clear LOS, then an explicitly relocated legal target overlaps the annulus across a real contour. The native ray hits contour0 and prevents damage. No collision data or geometry is replaced
- Formal town return removes sources and cancels the pending annulus. On a second fresh formal entry, actual shared-defense source death during the outer warning immediately cancels it; advancing afterward never emits the canceled pulse

## Scope and controls

This is focused integration evidence, not natural-play footage, full-map combat completion, a migration suite or a full regression suite. Main processing is driven explicitly by `tick`. Auto-fire is disabled. All other admitted roots remain resident; their movement speed is set to zero and attack timers are held. Probe resets, boundary positions, native-wall source/target positions, health/shield/evasion, one freeze, one invulnerability interval and one lethal settlement are explicit QA controls. Actual root admission, native physics, ordinary held-input movement, telegraph runtime, damage defense, town return and death cancellation are production paths.

## Reproduce

With the project's asset/class import cache present, from the project root:

```sh
qa_profile=$(mktemp -d /tmp/godot-m1-v120-main-XXXXXX)
mkdir -p "$qa_profile/data" "$qa_profile/cache" "$qa_profile/config"
XDG_DATA_HOME="$qa_profile/data" \
XDG_CACHE_HOME="$qa_profile/cache" \
XDG_CONFIG_HOME="$qa_profile/config" \
RUINS_BOSS_MAIN_OUTPUT="$PWD/docs/qa/v120-ruins-boss" \
timeout 45s /usr/local/bin/godot4 --headless --path . \
  --script res://tests/ruins_garden_boss_main_test.gd \
  > docs/qa/v120-ruins-boss/main-run.log 2>&1
```

The test refuses an existing `user://build_save.json` and requires an isolated `/tmp/godot-m1-v120-*` profile. It writes only the `main-*` evidence files in its selected output directory and the isolated user profile.

## Import caveat and historical evidence

The new worktree initially lacked imported textures and generated class metadata; `main-preflight.log` records that failed preflight. A bounded editor import then created the cache and returned0. `main-import.log` also records editor-config persistence errors and two historical documentation-picture import failures (`docs/qa/v116-ruins-garden-entry/native-entry.png` and `docs/qa/v118-ground-dressing/native-map.png`, `ERR_FILE_CORRUPT`). These are historical QA images, not runtime textures needed by this test. They were not rewritten. Import-created untracked historical `.import`/`.gd.uid` metadata was removed; no historical test or evidence file changed. For a future cold-cache import, temporarily exclude documentation with `docs/.gdignore` before the editor scan and remove only that temporary exclusion afterward; also use isolated XDG config/data/cache directories.

The v116 `tests/ruins_garden_entry_test.gd --boss-only` assertion that native and old garden attacks have identical profiles/targeting is now deliberately stale. It remains unchanged, along with its historical QA receipts. This new test supplies current behavior evidence without retroactively changing that result.

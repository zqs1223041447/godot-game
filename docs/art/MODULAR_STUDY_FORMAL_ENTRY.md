# Modular study: playable closure and formal-entry conditions

v115 update: the isolated study now has pre-fee native preparation, same-instance
admission, bounded detours for the two blocked routes and ordinary-retry cleanup.
See [v115 entry evidence](../qa/v115-native-map-entry/README.md). The v114 audit
below is retained as historical evidence; its first two entry gaps are addressed
by the opt-in adapter. A new formal map identity/progression contract remains
unselected and no production menu entry is added.

This read-only v114 follow-up is based on v113 `bf8aacfb2c13b96fb6f489338fa7a7252ab190df`. It adds one focused integration fixture and evidence, with no gameplay, geometry, art, map catalogue, save schema or economic changes. The independent research area is playable through the existing completion/return/claim loop. It is **not yet a formal selectable map**.

## Verified current loop

The test starts the real Main scene with a fresh isolated ordinary character, prepares free old_garden tier I, and admits its original 25 roots. Installing the current four native contours requires zero spawn remaps. Original actor, Main, model, RNG and save bytes remain equal through installation and all spatial queries.

At the actual player radius 15, native direction/move queries produce continuous swept paths through all six outpost centers, the original boss location and back to entry. All 25 unchanged initial actor positions are also individually reachable from entry. Requested spatial steps are 32 world units (hard maximum 40); each returned segment is checked against the native circle sweep. The largest observed segment is 32.00011444091797 world units. This sampler does not relocate the live player or actors, advance battle time, simulate player input, or claim a natural full-clear playthrough.

The unchanged `complete_boss_first()` helper from `tests/exploration_main_flow_test.gd` then uses real Defense receipts with controlled lethal damage. It checks early boss death, four original boss children, a held living descendant preventing completion, bounded descendant draining, one reward per original root, retained source records, repeated-death/completion idempotency, and town-only claiming. All six outposts clear, all 25 root kills persist, and the original four-shard tier-I reward is held for claim. Disk reloads before and after the actual town claim reproduce the canonical model; one claim gives four shards, clears the pending receipt, and rejects a second claim without state/RNG/save changes.

Town return releases the native physics space/bodies/shapes, study ground/marks, modular props and temporary hero selection. Original materials and town geometry return. Existing v112 actual input/projectile/three-monster gate traversal and native three-kill evidence are reused, not repeated. The current query sample does not establish every monster's long-range navigation at every radius, all future seeds, paid-entry fault handling under new native geometry, FPS, or final art acceptance.

## Smallest remaining formal-entry work, in priority order

1. **Prepare native geometry and validate before fee/save/live admission.** `scripts/studies/modular_study_session.gd::install()` currently operates on an already admitted isolated old_garden run and waits two physics frames before native readiness. A formal entry must prepare the native space, wait for readiness, and validate the complete route/spawn plan before `Main.start_map()` reaches `state.normal_start_map()`. Commit the same validated instance. `Main.restart_run()` currently refreshes the existing `_geometry`; it does not adopt the `geometry` returned in the plan. Failure must leave fee, save, runtime IDs, RNG and current scene intact. This is not achieved by adding the study launcher to the town menu.
2. **Resolve two actual authored-route conflicts using the same four contours.** The existing formal route predicate checks half-width 36 for the original 72-wide routes. The unchanged current study has these two conflicts out of twelve: segment 0, `(362,2184) → (1342,2104)`, intersects contour 3 (rock); segment 10, `(1342,2104) → (1882,1404)`, intersects contour 2 (arch leg). Their endpoints are clear. All six center/sign checks pass at their authoritative radii 27.5/15. Player-radius paths passing does not satisfy the wider authored-route contract. Reroute those two centerlines or author their required width against the native geometry, then validate every route and spawn before entry. The three paths excluded by v113's more conservative visual-paint radius 57 are a different measurement and are not these two formal failures.
3. **Add an explicit formal identity/progression/presentation contract only when that scope is chosen.** The study currently reuses old_garden, with an isolated save and no new map choice. A separate 25-root map needs explicit map/normal catalogue entries, layout/geometry dispatch, journey vocabulary and migration for its own tier key. `MapCampState._landmark_reason()` currently expects eight roots per original source group only for old_garden, twelve for every other ID; a new 25-root ID must not accidentally inherit the 37-root rule. The presentation manager and natural-ground geometry fingerprint also need an explicit mapping to the exact admitted assembly. New fees, rewards and a static-hero default are not implied by this audit.

These are bounded integration conditions, not a request for a new navigation framework. Preserve the existing four-contour/99-vertex limit, three translation-only modules, shared move/projectile/LOS truth, 100-entity cap, original map definitions and empty future-mechanism configuration unless a separate change deliberately revises them.

## Evidence and limits

See `../qa/v114-modular-map-closure/README.md`, the original full result and the narrow saved-only follow-up. The first run's sole failure was a test assertion hard-coded to historical schema 50; current Rules.VERSION is 53. It is retained as a fixture failure, not misreported as a production save defect. No full-flow rerun, new resource import, old-suite rerun, Windows export, full F8 regeneration or new asset download was needed.

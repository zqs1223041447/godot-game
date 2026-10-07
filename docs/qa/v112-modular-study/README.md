# v112 bounded integration evidence

Base: v111 `34d161581ccdd81d80037950aa2a4efe49b13590`, itself based on the independent v110 adapter. Main remains `e2fa6db`. No formal map, save schema, economy, original collision code, monster definition or projectile implementation was changed.

## Geometry

The first direct engine run executed 210 checks. Fifteen assertions failed in one left-arch-leg horizontal probe: its start was inside the neighboring short wall, so the native first hit correctly reported wall 0. Another probe ended in a neighboring collider. The test now validates clear endpoints and first-hit identities using vertical crossings; no collision rule was loosened. The run also exposed a RefCounted PREDELETE helper call after the reference became invalid; cleanup now frees its RIDs inline.

Only affected blockers, input validation and native lifecycle groups were rerun: 191 checks, zero failures, exit 0. Earlier arch passage and finite route checks passed and were reused. The diagnostic log retains the original bad endpoints and true native collision IDs. `geometry-source-attempt01-current.gd.txt` was copied after the first run, including a later cache-clear line; it is explicitly not claimed as the exact source loaded by that process. The original test source and process output are preserved; subsequent input hashes are recorded.

## Module presentation

The first attempt did not enter tests: its EXPECTED dictionary missed an outer closing brace. The next run executed 384 checks, with 14 failures on repeated mipmap readbacks. The first seven resource checks had passed; the test then called clear_mipmaps on the shared readback Image, altering later inspections. The correction duplicates the Image before this destructive inspection, retaining the real mipmap assertion and original pixel checks. The loader now also records the observed pre-upload mip count, uses non-logging JSON.parse for expected invalid fixtures, and rejects a source zoom other than the authored 0.65.

Only resources and rejection paths were rerun: 109 checks, zero failures, exit 0. Existing ordering, identity, translation, clear ownership and old-path checks are reused; counts are not added as disjoint suites. Seven original PNGs and their shared feet remain unchanged. No collision nodes are created by the presenter.

## Actual Main

The first effective Main run executed 64 checks, with one cross-run landmark comparison failure. The other 63 passed:

- Legal old_garden tier-I admission: 25 initial roots, zero remaps, source positions clear, install-time model/roster/player/RNG/save bytes unchanged
- Four original contours and 99 original vertices, three module bodies, static hero foot alignment, unchanged 0.65 camera and player radius 15
- Four actual held-movement wall probes, one legally owned dash, four actual projectile wall collisions and one projectile through the open arch; Main LOS uses the same contours
- Three simultaneously active original enemies (skitter radius10, crawler14, original rift_warden27.5) crossed the gate under actual Main.tick in 286 steps / 4.7667 simulated seconds. All sampled movement segments remained clear, all25 identities persisted, and the other22 original actors remained at sleeping source positions. These later positions were explicit test inputs, not natural-play or old-map combat/RNG equivalence claims
- Town cleanup removed native study collision, module bodies and temporary hero selection

The one failure compared old and new run `outposts.root_ids` for exact equality despite the existing monotonic runtime ID cursor. A reentry-only diagnostic was added. Its first attempt had a test-local inferred boolean parse failure; explicit bool fixed that fixture. The narrow effective rerun passed 15 checks, zero failures: all new IDs are exactly26–50, six outpost root-ID arrays match each run's own source group/ordinal/position/actor records, and every other landmark field remains exact. No production code was changed for this test correction, and movement/projectile/crowd checks were not repeated.

## Native observation and scope

Root ran the real study on 2026-10-07 18:13–18:16 UTC: W/D movement, following camera, three actual kills (HUD remaining25→22, experience15), W through the arch and S return, with correct occlusion/reappearance. The unchanged screenshot and bounded observation are recorded in native-observation.json. Old repeated ground tiles remain a visible quality issue; this is technical integration evidence, not final art acceptance, animation completion, Windows validation or FPS measurement.

One normal editor import was performed for the new checkout. v111's original Blender/201-pose checks, historical game suites and long soaks were not rerun. No new assets were downloaded, no Windows executable/Release was created, and original v111 archive hashes still match. Source identity checks are in source-scope.json.

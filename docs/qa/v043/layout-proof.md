# v0.43 fixed camp layout proof

Focused command: `bash tools/validate.sh res://tests/map_camp_layout_test.gd`

Godot 4.6.3: **5,597 checks, zero failures**. All six canonical normal map/tier profiles, six distinct camp arrangements, and 210 routes through the existing movement/navigation implementation passed. The runner isolates Linux settings, cache, and saves and rejects Godot script errors even if Godot exits zero. No scene was instantiated and no editor/resource import or history suite was requested by this check.

## Source identity

- Production layout SHA-256: `817993ab023c7dc4cbc37af67a78a4b6ecd684f04bc94ee8fe38d11982d7cbd7`
- Proof test SHA-256: `c0eadc7c117d2587b4f8e30e7016ac5480696417fcb0fb63c6a7aaa5c0e8cfb4`
- [Full 22-file source/dependency manifest](layout-source-sha256.txt)
- [Command, engine, timestamps, full hashes, and log hash](layout-evidence.json)
- [Final raw output](layout-final.log)

The complete source/data dependency closure was hashed immediately before and after the final run and was identical. The Git HEAD in the evidence is contextual only: these are uncommitted shared-workspace changes, so the full file hashes identify what was actually exercised. No index or commit operations were performed.

## Fixed layout and bounds

The actual `WorldView.WORLD_ARENA` is position (42, 104), size (1840, 710.7693). Every approved coordinate is added to the bounds origin. The helper accepts the current or a larger layout envelope (minimum 1840 × 710), including translated origins, without scaling coordinates. It rejects unknown/non-String map IDs, undersized/negative bounds, nonfinite position/size/end, and finite origins so large that Vector2 precision would erase the layout offsets. Rejections contain a nonempty reason and an empty landmarks dictionary.

Each camp's array contains the complete 4 × 2 old-garden or 4 × 3 ruins formation. Fresh calls and sibling formations own separate mutable arrays/dictionaries. The helper performs no RNG, scene, actor, or collision mutation. The existing MapGeometry remains the collision authority.

South-edge boss trigger disks extend beyond the arena. Their centers and all actor bodies are inside the arena. The proof deliberately uses the entire trigger disk, which is a conservative superset of reachable player activation positions.

## Spatial proof

Actual profiles are compiled for old_garden tiers I/II/III (waves 1/4/8) and broken_ruins tiers I/II/III (waves 2/5/9). Their root targets are respectively 24 and 36, exactly the sum of their three full groups. Bodies are built through the real MonsterCatalog, including every ordinary/elemental/death template; maximum ordinary radius is 22 and the actual rift_warden radius is 27.5.

For root center S, trigger center T, radius R = 64, and any activation position P satisfying |P − T| ≤ R, the triangle inequality gives |S − P| ≥ |S − T| − R. Evaluating that lower bound for every root proves the whole continuous disk, rather than only its center or sampled angles.

- Minimum root-center distance to its full activation disk: **301.075348**, exceeding the required 230
- All roots also meet 230 against each of the other camp trigger disks
- Minimum boss-center distance to its full activation disk: **251**, exceeding 230
- Minimum separation of any pair of simultaneous maximum-radius root bodies: **12**, so all 24/36 root circles are disjoint
- Every formation center and member body, entry body, boss body, and player trigger-center body clears actual bounds and actual ruins walls
- Entry is strictly outside every camp trigger

The 210 navigation routes cover entry to every choice, every ordered camp-to-camp pair, every camp to the boss trigger, every root position to its trigger with the maximum body radius across all six profiles, and each actual boss to its trigger. Each route uses MapGeometry.direction and MapGeometry.move in 5-unit steps, checks every result is clear and every actual segment is unoccluded, and requires arrival within 0.05 units. The ruins entry-to-east path is explicitly verified to have a blocked direct line, ensuring this proof exercises a real wall detour.

## Segment activation

`trigger_crossed` computes inclusive finite-segment/circle intersection by projecting the circle center onto the clamped segment. Scalar double arithmetic avoids Vector2 squared-length overflow for large finite coordinates. Tests cover entering, exiting, outside-to-outside crossing, a 175-unit dash through the 128-unit disk, exact tangency, near-tangent misses, endpoint contact, line-only misses, stationary inside/boundary/outside, diagonal travel, translations, reversed endpoints, zero-radius points, nonfinite vectors/radii, negative radius, and very large finite inputs. The caller must supply actual validated movement segments; this pure helper does not authorize movement through walls.

## First-run correction and limits

[Initial output](layout-initial.log) captured a typed-array assignment error in the newly added helper; Godot does not infer a typed array from these conditional expressions. The helper now fills typed arrays with assign(), and the proof has an independent final coverage assertion so early test-method aborts cannot report a successful incomplete coverage count. The [first clean recheck](layout-recheck.log) passed 5,579 checks; the final 18 additional checks explicitly verify formation-center clearance at each profile's maximum radius.

This evidence establishes pure layout and segment-trigger geometry. Runtime activation state, encounter admission, rendering, and end-to-end UI behavior are owned and verified by their respective integration work.

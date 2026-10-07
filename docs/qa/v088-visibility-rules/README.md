# Retained visibility focused verification

This directory records the single focused `tests/retained_visibility_test.gd` run for the offscreen retained-actor change. Production performance is measured separately by the parent task. This is a headless command-geometry and lifecycle check, not a screenshot, pixel comparison, full historical test run, or performance claim.

## Result

The first and only run passed on Godot 4.6.3: **4,982 checks, 0 failures**, process exit 0, and no `SCRIPT ERROR` or `ERROR` in the preserved log. It captured **832 geometry cases, 33,984 production draw commands, and 319,200 command vertices** across all 10 catalog templates. Test-body time was 0.280 seconds; complete process wall time was 1.424 seconds. The smallest observed radial slack before the extra antialiasing allowance was 9.027 arena units (ember guard). The widest actual stroke was 6 units.

The result's SHA-256 fields match the files after the run:

- Retained layer: `959d0f102e8ae255cb8ca2420c11e6c2b114f1f3d476fcb433e12cd0e455bb20`
- Production art: `6d1948000018b03af847f4d297b32acb83c3f8e5397f87b960b384f45882bf6a`
- Focused test: `a9b8d4c0a4dc8d775d7078af682661dc0cfc003ce9d4a7334de055ca721b65b9`

## Geometry oracle

The test reads the current `fantasy_actors.gd` and compiles an in-memory copy that removes only its global class registration and changes `CanvasItem`/`Node2D` argument annotations to `Object`. Every production drawing statement, coordinate formula, contour-cache operation, branch, and draw order stays unchanged. A command spy receives the actual polygons, polylines, lines, circles, and their widths. There is no checked-in alternate art implementation and no native-method override assumption.

Every authored catalog template is exercised with every legal ordinary rarity (normal, magic, rare); the catalog-restricted mist skitter uses normal and the rift warden uses boss. Tests use each catalog radius plus 0, 36.125, and 120.25. For each, gait is evaluated at -1.2, 0, +1.2 and with motion disabled, with flash both off and on. The shadow, dynamic limbs, and static body paths must each emit commands. Captured bounds include circles and half of every stroke width. The checks also verify that flash does not alter geometry and motion-off limb commands do not change with elapsed time.

The continuous bound is conservative: every current animated coordinate is affine in gait; gait lies in [-1.2, 1.2]. Rounded contours are convex combinations of their control points. Therefore the two gait extrema bound intermediate poses, including wings and feet. Current non-stroke geometry fits the local square `|x|, |y| <= 1.5*r+8` for nonnegative radius. Wings reach at most `1.5*r+0.9`; scavenger toes reach `1.03*r+3.2`; ember feet include offsets no greater than 4; skitter tails reach `1.32*r`; warden horns reach `1.24*r`; the shadow reaches `r+4` horizontally and `0.92*r+3` vertically. Other body parts and elemental/mist crests fit inside these limits. The largest actual stroke is 6 units, so half-width adds 3. The test measures radial distance of every captured endpoint/contour point (plus circle radius or half stroke width), which covers every continuous facing angle, not only sampled rotations.

The visibility margin is `sqrt(2)*(1.5*max(r,0)+8)+3+AA`. `AA = 2*(|inverse.x|+|inverse.y|)` conservatively maps two screen pixels on both axes into arena space. The test checks identity, translation, zoom out/in, rotation, nonuniform scale plus shear, and a transformed arena. Expected local view bounds are computed from independent min/max accumulation of all four inverse viewport corners. All padded sides and selected corners are inclusive; points just beyond each side are excluded. Invalid frames, singular real transforms, and nonfinite actor radius/position fail open.

## Retained lifecycle

The fixture uses real Node2D pieces, a fixed-size SubViewport, the real catalog, and an actual Camera2D pan/zoom/rotation. Checks cover:

- Three pieces are allocated for every live ID, including initially hidden actors
- Hidden admission skips configuration/redraw; an already visible actor becoming hidden keeps its body key, transform, elapsed time, and redraw count
- Every live triplet participates in complete y ordering while all surviving node identities remain stable
- Camera translation re-entry immediately configures the latest position, facing, radius, flash, elapsed time, and preferences
- A radius increase alone can make a hidden actor visible, and flash ending while hidden is current on that same sync
- A hidden actor's death immediately detaches and queues all three pieces; clear/re-entry reconstructs only live actors
- Each sync compares exact serialized enemy/host/preference bytes before and after, and the complete check preserves the global RNG stream

No screenshot or historical suite is required by this focused check. The run is isolated with fresh `/tmp` XDG directories and does not read or write a player save. `result.json` contains source hashes, case counts, measured safety slack, transform summaries, and runtime; `run.log` and `run-result.json` preserve the process result.

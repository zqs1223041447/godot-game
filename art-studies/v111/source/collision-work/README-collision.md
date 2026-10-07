> 归档说明：本目录保留原碰撞推导与验证记录。`verify_collisions.py` 与 `setup_modules.py` 的祖先身份比较/重建依赖未附带的同级v108原工作目录，详见顶层README“归档可搬迁边界”。现成Godot小样与规范化模型重渲染不需要该祖先目录。以下原记录不是本紧凑包可单独重跑全部历史源比对的承诺。

# Three independent modular ground-collision contracts

## Output and checks

Main output: `../../exports/collisions.json`

- `short_wall`: 1 solid outline, original source `Low west wall • vegetation-softened edge`
- `walkable_arch`: 2 disjoint structural-leg outlines, original source `Hero arch • authored gate • worn crown`; both actual `walkable_arch` and `walkable_arch_sill` meshes are included in extraction
- `moss_rock`: 1 conservative convex outline, original source `Scanned moss rock 01`
- Total: 3 reusable modules, 4 valid outlines, 99 exported boundary vertices
- Flat local receiving ground: z=0; the full module low-vertex foot is the common local (0,0,0) anchor
- Only translate instances in XY. Original orientation and scale are already baked into the actual source meshes and colliders; do not rotate, mirror, or rescale

The extraction reads finalized `source/modules.blend` and `source/module-definitions.json`, never saves or renders them, and preserves all three source objects' triangle counts (406, 896, 11000). The original source and normalized module geometry agree within 0.000001067m after applying the recorded translation. Arch seams have duplicated vertices because the sill was separated, but all original triangles remain. The frozen v108 source, derivative module blend, and module-definition SHA-256 values were rechecked unchanged.

## Gate passage

- Raw actual body-height opening: approximately 2.625997m
- Exported buffered-collider opening: approximately 2.575997m
- Available center-position width for a radius-0.30m character: approximately 1.975997m
- Actual sill top: 0.150079146m above the flat receiving ground
- A 1.8m body is tested through the whole band from -0.001m to sill-top + 1.8m + 0.001m
- Actual mesh sections at sill + 0.10m, +0.90m, +1.80m all retain two separate legs and approximately 2.626m opening
- The true radius-0.30m sweep along the provided gate centerline has at least 0.987998725m lateral clearance after accounting for the body radius
- Conservative overhead clearance above the sill along that tested sweep: 2.628728971m

The low sill is deliberately walkable only inside the actual opening; wall-leg foundations outside it stay solid. This is not a jump/step simulation. A 3D controller must support a step of at least 0.151m or an equivalent ramp; a flat 2D controller treats the visible sill as passable ground.

## Margin and geometric error

The procedure follows the existing collision contract: clip actual mesh triangles to the body-height band, union their ground projections and clipping-plane sections, then use 8mm topology-preserving simplification, a nominal 25mm outward buffer, and 1mm final simplification. The complete original blocking base is covered in every output after the low-sill exemption.

25mm is a nominal intermediate buffer, not a guaranteed uniform 25mm gap from the actual source surface. Measured minimum final offsets from each unsimplified base after serialization:

- short wall: 19.550199mm
- arch: 17.172379mm
- rock convex hull: 18.888824mm

The maximum simplification-plus-buffer displacement bound is 34mm. Section endpoints are snapped to 0.0000001m; serialized metre values use 0.000000001m precision. The rock's convex hull additionally fills concave notches/scan gaps, adding 0.412297897m² versus the actual body-height raw projection; that intentional conservative filling is not covered by the 34mm bound.

## Coordinate usage

Every polygon outer ring provides aligned arrays:

- `ground_xy_metres`: module-local ground vertices, z=0
- `foot_relative_screen_pixel`: offsets from the sprite's physical foot, NOT coordinates inside the cropped sprite
- `full_frame_screen_pixel`: the same offsets added to [640,360]
- `godot_local_world`: offsets from the Godot instance's ground-foot origin

The metre outer rings are counterclockwise, with no repeated endpoint. The Y flip reverses pixel/Godot winding. There are no polygon holes in these four output outlines.

For pixel placement, use screen X=640+47.407407407407405*x and screen Y=360−38.83387469221887*y−27.191771797382927*z. Collision z is always zero. For a cropped sprite, its physical foot is [640−crop_left,360−crop_top]; add each foot-relative collision pixel to that foot. Do not use sprite silhouette or alpha-bottom as the ground anchor.

Godot local X=72.9344729345*x and local Y=−59.7444226034*y. A .3m metre-space circular body maps to an ellipse with Godot radii [21.88034188035,17.92332678102]. The colliders do not already contain the character radius. A same-radius Godot circle is not equivalent under this anisotropic projection.

The analytic camera projection agrees with Blender's actual camera to under 0.0001 pixel at all five tested references. Serialized collision-coordinate conversion error is below 0.000000001 pixel/unit.

The specified low-vertex foot method leaves a harmless float residual up to 0.000000239m. For the rock, high geometry extends forward to local y≈−0.379923m; a foot derived from low vertices does not imply every collider or visual point has y≥0.

## Scope

The modules are independent local assets, not three objects superimposed at one shared scene origin. Their assembled placement must be checked separately. No Godot physics integration, final layout traversal, character animation, or visual Y-sort/occlusion test is claimed. Large walls and arches may require split visual layers/anchors.

No source scene was changed, no Blender rendering was performed by the collision work, no new assets were downloaded, and no v108/v109 file was written.

## Reproduction

1. `blender --background --disable-autoexec --threads 4 --python source/collision-work/extract_modules.py`
2. `/usr/bin/python3 source/collision-work/build_collisions.py`
3. `/usr/bin/python3 source/collision-work/verify_collisions.py`

Uses existing Blender 4.3.2, NumPy, SciPy, and system GDAL/GEOS. Detailed independent checks are in `independent-verification.json`; the final mesh extraction and exact unsimplified WKT bases stay beside these scripts for reproducibility.

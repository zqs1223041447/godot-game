v105 dimensional environment: original Blender model source

Files:
- build_environment.py: deterministic mesh/material/light/camera authoring
- environment_native_preview.blend: native three-object showcase source
- environment_native_preview.png: native Cycles preview, no painted composite
- export_sprites.py: approved-only three transparent module renders
- environment_manifest.json: dimensions and (after export) exact pixel anchors

Rebuild preview (run inside this directory):
blender -b --python build_environment.py
blender -b environment_native_preview.blend --python refine_preview.py
Export approved transparent sprites:
blender -b environment_native_preview.blend --python export_sprites.py

The checked-in .blend already contains the refinement. Export it directly;
refine_preview reverses selected face normals and must not be applied again.
Only apply refine_preview once after a fresh build_environment generation.
Python outputs are relative to the script directory, not an old art-work path.
refine_preview explicitly resets the PNG output path when the .blend is moved.
Native interactive Render may still use the original path stored in the .blend;
choose a new output path in Blender before rendering it manually.
Exact PNG bytes are not promised across Blender/render-engine versions.

Runtime convention:
Blender unit = 20 Godot world units. Ground X is unchanged. Ground Y is divided
by sin(55 degrees), so the 55-degree orthographic projected base footprint has
the specified Godot world width and depth. Blender -Y maps to screen/Godot +Y.
Z is visible vertical height only. Rendered scale is exactly 2 px/world unit;
export_sprites.py measures the camera's actual projection to establish it.
anchor_px is the projected FRONT EDGE CENTER of the declared footprint.
base_center_anchor is the projected ground-plane origin. visual_bounds is the
actual alpha>1/255 bounding box [left,top,right-exclusive,bottom-exclusive].

Intended final paths:
assets/environment/ruin_wall.png (96x64 footprint, wall stone 70 high)
assets/environment/stone_planter.png (160x120 footprint, stone 45 high)
assets/environment/ginkgo_tree.png (80x80 base footprint, canopy extends past it)

The wall is a short sorting module, never one stretched long-wall sprite.
Use only pre-existing obstacle footprints. Ginkgo trees belong in existing
blocked terrain or beyond the map perimeter. No new collisions or map layout
changes are required or authored here. A planter's flora projects above its
45-world-unit stone rim. Ground shadow-catcher planes are excluded from sprites.
The preview's floor and display separations are SHOWCASE_ONLY.

Geometry:
Individual rough beveled masonry stones with independent coping; deep plinth
steps and rim, real recessed soil and botanical relief; tapering forked ginkgo
branches with over 2,000 individual folded bilobed leaves in open layered sprays.
Original deterministic authored meshes (seed 10573), procedural PBR materials.
No downloaded assets, external artwork, paint-over, or paid resources.

Lighting: fixed upper-left warm area key, soft neutral/cool fill, broad warm rim.
Cycles CPU. This Blender build lacks OpenImageDenoise; use_denoising is False.

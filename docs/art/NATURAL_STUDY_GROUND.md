# Natural ground in the independent module study

This study replaces the repeated large stone-tile base only when the explicit v112 `modular_study` geometry is active. Run `bash tools/run_modular_study.sh` in this branch after resource import. Main's ordinary maps and town keep their original environment; the normal game branch is unchanged.

## Presentation and cost boundary

One child CanvasItem draws one opaque quad, using three original CC0 diffuse textures and one fixed 512×384 RGBA blend mask. It has no process callback, TIME, screen UV, route loop, gameplay RNG, new physics or per-frame data generation. The material belongs only to this ground child. Separate retained ground markings, flags, character bodies, module shadows and sill keep their ordinary materials and draw order. Returning to town removes the study ground and restores the original renderer.

Soil and two differently scaled grass samples provide detailed earth and broad variation. Stone is confined to locally worn route sections. The fixed grass/soil mask and source texture detail use different scales to reduce obvious periodic patterning. The shader does not claim to recreate Cycles/AgX lighting or add dynamic ground lighting.

Authored source density follows the existing v108 material choices: soil .31 repeats/metre, grass .085, secondary grass .063, stone .50. Source-ground metres use 72.9344729345 world units horizontally and -59.7444226034 along Y, including the original source projection conversion once. The current camera applies its own zoom once afterwards. At the .65 reference zoom, soil repeats about153×125 screen pixels, main grass558×457 and stone95×78. These are authored material scales, not newly measured scan dimensions.

Camera movement changes the normal canvas transform, not the retained quad, textures, mask or UV origin. The shader's cost is bounded to five texture samples per visible fragment: three material roles, a second grass scale and the blend mask. This is an implementation bound, not an FPS claim. The four resources are loaded once per instance; changed/invalid contour fingerprints reject the mask and restore the original environment rather than silently painting the wrong layout.

## Fixed route mask

`tools/build_study_ground_mask.gd` is an offline preparation tool, never called by Main. It uses local FastNoiseLite seeds113 and1137; no gameplay random generator is accessed. The frozen mask is committed, so normal play does not recreate it.

Candidates are the existing12 authored Old Garden route segments and one source-verified gate approach. Original module contours, not old empty-map checks, validate every full painted corridor. Ten pass; three are omitted because they meet the new rock, short wall or arch leg. Neither routes nor physical geometry are rerouted or edited. Only presentation paint is filtered.

After one native visual review, the maximum paint width was changed48→64 world units (1.33×), within the requested1.4× bound. A fixed140-world-unit wear field shrinks the painted edges and exposes local grass/soil gaps. It does not displace the centerline or enlarge paint beyond its validated envelope. Native clearance radius is57 =32 paint half-width +10 filtering margin +15 actual player radius. The final mask still uses the same ten accepted routes.

To regenerate intentionally in a working copy: `godot --headless --path . --script res://tools/build_study_ground_mask.gd`, using isolated XDG directories. This writes the mask/profile and its QA record. Import the changed mask afterwards. Preserve old evidence before regeneration. No Blender re-render, scene-capture tiling or new asset download is involved.

## Evidence and remaining limits

The actual Main ground check passed27 assertions on its first run: isolated material ownership, fixed camera/world coordinates, no draw/material/node rebuild on camera movement, unchanged map/roster/collision/RNG/save bytes, rejection/fallback and real town cleanup. After the one wear adjustment, only its17 mask/resource/native-clearance checks were run; the earlier Main checks were not repeated.

Root observed the initial grass/soil floor while moving with W/D and saw no obvious jumping or seams. At19:09 UTC, the final worn-path version was observed during D movement and documented in `docs/qa/v113-natural-ground/native-observation.json`. This is local visual evidence of this region, not universal seam proof, final whole-game art approval, a Windows test or an FPS measurement. Hero direction images remain static; this batch does not add animation or change the scene modules.

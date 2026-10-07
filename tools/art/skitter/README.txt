FEATHERBACK SKITTER / 甲羽掠行体
Original six-legged garden creature, built entirely from procedural custom cross-section meshes.
This asset is independent of the rock quadruped silhouette: narrow chest, long segmented abdomen,
bent spring legs, visible wedge head, two tiny amber eyes, swept overlapping shell-feathers,
and sparse age-worn copper throat guards. No downloaded models or textures.

DELIVERABLES
- skitter_atlas.png: 2048 x 1728 RGBA, 16 columns x 9 rows
- atlas_metadata.json: contract, each native frame bounds, render settings, SHA-256, QA
- frames/000.png through frames/143.png: 128 x 192 RGBA native renders
- skitter_sample.png: true 256 x 256 transparent Cycles render
- direction_contact_sheet.png: labeled 8-direction inspection image
- skitter.blend: reproducible model, materials, fixed camera and lights, SE idle pose
- generate_skitter.py: mesh construction, procedural animation, rendering, atlas packing

SPRITE CONTRACT
Direction 0 E, 1 SE, 2 S, 3 SW, 4 W, 5 NW, 6 N, 7 NE.
Model forward is local -Y. Root yaw = 90 - 45 * direction degrees.
Idle 4 frames offset 0; walk 8 frames offset 4; attack 6 frames offset 12.
Index = direction * 18 + offset + frame. Playback 12 fps.
All frames share ground-origin anchor (64,142). No per-frame cropping, shifting or resizing.
Walk uses opposing tripod phases: left front + right middle + left rear, then the other three.
Attack is anticipation, forward reach, lunge, recovery. No animation-driven damage events.
A single orthographic scale is fitted against all evaluated meshes over all 144 poses.
Do not use the directional contact sheet as the production texture.

RENDERING
Blender 4.3.2, Cycles CPU, fixed 3 threads. Denoising disabled (CPU has no OIDN).
Fixed orthographic 55-degree camera (0,-10*cos55,10*sin55), looking at origin.
Key light fixed in world coordinates (-3,-4,8), warm white 550 W large area light.
Cool secondary bounce and muted studio environment. AgX Medium High Contrast.
No floor, no baked shadow, no black background. The game supplies the shared ground shadow.
PNG pixels outside silhouette have genuine zero alpha.
Atlas frames use 40 samples; sample uses 56 samples.

REPRODUCE (from any working directory)
blender -b -t 3 --python /full/path/generate_skitter.py -- --sample
blender -b -t 3 --python /full/path/generate_skitter.py -- --all
python3 /full/path/generate_skitter.py --pack
Packing refuses missing, clipped or mismatched native frames.
Suggested game scale is provisional. Parent integration must tune final uniform display scale
against measured alpha bounds and the 40-45 world-unit body-height target; long legs widen
silhouette without implying the body needs crawler size.

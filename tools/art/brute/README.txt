HEARTHWARD / 遗迹重甲守卫
Original medium-poly articulated stone-and-old-copper upright guardian.
Authoring and packaging stay in this directory; no game source changes.

Reproduce sample:
blender -b -t 3 --python generate_heavy_guard.py -- --sample

Reproduce 144 frames (only after sample review):
blender -b -t 3 --python generate_heavy_guard.py -- --all
python3 pack_heavy_guard.py

Contract: RGBA PNG; 128x192 per frame; 16 columns x 9 rows, 2048x1728.
8 directions E, SE, S, SW, W, NW, N, NE; yaw = 90 - 45 * direction.
Animation idle 4, walk 8, attack 6; offsets 0, 4, 12; 12 fps.
Index = direction * 18 + animation_offset + frame.
Foot anchor is the genuine projection of WORLD (0,0,0), at (64,158).
All frames share exactly the same camera and global fit. No per-frame cropping.
The frame does NOT imply that every visible toe lies exactly at anchor y=158:
projection gives fore/aft feet different y values. Use the world anchor for
shared shadow and positioning, and metadata alpha bounds for visual extents.

Fixed camera at (0,-10*cos(55deg),10*sin(55deg)), aimed at origin;
vertical orthographic fit and lens shift preserve projected world origin.
Main area light (-3,-4,8), fixed in world as model turns; cool soft fill.
Cycles CPU, exactly 3 threads, denoising disabled. No external models/assets.
No ground, no baked shadow, no glowing emission or gameplay VFX.
Animation timing conveys weight; gameplay damage timing remains game-owned.

The sprite is intended for the brute/heavy-guard family. Final in-game scale
and shared ground shadow are set by the integrating parent task.
Full real-alpha bounds, projected head anchors, camera, and SHA256 checks are
recorded in atlas_metadata.json and frame_table.csv after packaging.

Final QA: all 144 frame files exist, source mode RGBA, exact atlas tile match,
no alpha touches any frame edge. Shared origin is [64,158] in every frame.
S-facing idle body: 96px. Suggested uniform scale: 70/96 = 0.729167.
All-frame body heights: 88..117px. Whole-atlas alpha union: [5,62,123,185].
136 unique renders are intentional: attack frames 0 and 5 are equal recovery
poses in each of 8 directions. 144 contractual slots are all present.
Atlas render: Cycles 40 samples, 3 threads, no denoise; 63.589 seconds.

# Rift Warden · 断冠遗迹守门者

Original three-dimensional ancient ruin gatekeeper: long sculpted stone mask, asymmetric broken architectural crown, stepped copper-stone shoulders, long olive ceremonial stoles and a split rear mantle, articulated massive arms, individual stone fingers and broad grounded feet. This is a separately built model, not a resized crawler or guard.

## Deliverables

- `rift_warden_atlas.png`: native transparent 2048 × 1728 RGBA atlas, 16 columns × 9 rows, 144 frames
- `rift_warden_manifest.json`: frame table, true foot and head anchors, alpha bounds, rendering and integration contract, SHA-256 and QA results
- `rift_warden.blend`: editable model with materials, articulated rigid-joint hierarchy and final render setup
- `generate_rift_warden.py`: reproducible procedural model, poses, render and atlas packer; supports arbitrary output directory
- `rift_warden_sample_256.png`: approved transparent 256 × 256 three-quarter sample
- `rift_warden_direction_contact.png`: all eight idle directions and approximate world-sized review row
- `rift_warden_animation_contact.png`: south-facing idle, walk and attack sequence

## Render and animation contract

- Native frame: 128 × 192 pixels, no per-frame crop, scale or center adjustment
- True world-origin foot anchor: **(64, 158)**, world point (0, 0, 0), constant for every frame
- Directions: 0 E, 1 SE, 2 S, 3 SW, 4 W, 5 NW, 6 N, 7 NE
- Model's forward direction: −Y; yaw = 90 − 45 × direction
- Index: direction × 18 + animation offset + local frame
- Idle: 4 frames, offset 0; walk: 8 frames, offset 4; attack: 6 frames, offset 12; 12 fps
- Idle is restrained breathing; walk is a heavy deliberate step; attack is a two-arm bent-elbow windup and forward downward slam
- These are visual frames only. No new attack rule, timing hook, damage trigger, particle or ground ring is introduced
- Fixed 55° orthographic camera. Sensor fit VERTICAL, ortho scale 5.2
- Fixed upper-left world-space key at (−3, −4, 8), plus soft fill; illumination does not rotate with the actor
- Blender 4.3.2, Cycles CPU, **3 threads**, 40 samples, no denoiser/OIDN requirement
- Transparent background with no floor geometry and no baked contact shadow
- Warm grey carved stone, tarnished old copper, deep olive cloth and a small amber core. No external models, images, purchases or downloads
- Recommended runtime uniform scale: **0.72**. Use the measured idle alpha height in the manifest to tune if the existing actor renderer applies additional sizing. Do not stretch width/height separately

`head_anchor_px` is the projected crown-top attachment point. `visual_top_anchor_px` is the rendered silhouette's top; raised fists may be higher during the windup. Both are in unscaled frame-local pixels. Apply the same actor scale and subtract the shared foot anchor when positioning runtime labels.

## Rebuild in any output directory

```sh
blender -b -t 3 --python generate_rift_warden.py -- --sample --out /path/to/output
blender -b -t 3 --python generate_rift_warden.py -- --all --out /path/to/output
python3 generate_rift_warden.py --pack --out /path/to/output
```

Packing uses Pillow and performs native-frame/pixel-equality, alpha-boundary and missing-frame checks. `--preview` renders four selected poses in every direction. `--indices 13,31,49` supports targeted rerenders with the identical global camera/anchor. The source file need not live in the output directory. Keep the generator with the deliverables for future rebuilding.

Review contact sheets have a flat olive background only for readability. The atlas and native frames retain real RGBA transparency. `frames/`, logs and contact sheets are review intermediates; runtime only needs atlas and manifest.

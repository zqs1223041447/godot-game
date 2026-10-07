# v105 actor/depth validation

Baseline: `181216b77b4f19078e5e33f6fd1b108afea828ca` on `codex/v105-dimensional-art`.

## Source contract

- `Main.world_depth` aliases the retained actor layer, a `Node2D` named `WorldDepth` with `y_sort_enabled=true` and `z_index=0`
- Hero, monsters, and the independent scenery manager's objects attach their foot roots directly to this layer; actor children remain one atomic Y-sorted unit
- `sync()` and `clear()` are retained. `clear()` removes only registered actors and the hero; independently managed scenery is preserved
- `ActorSpriteCatalog` shares two textures and scans alpha bounds once per asset. Both real manifest schemas supply their own foot anchor
- Eight directions are east, southeast, south, southwest, west, northwest, north, northeast. Each direction has idle 4, walk 8, attack 6 frames at 12 fps
- Hero scale is 0.5 and foot pixel is (64,158); crawler scale is 0.64 and foot pixel is (64,142). These are presentation values and never replace collision radii
- Atlas shadows are retained foot-local vector ellipses. Other monster families keep their original vector body/limb artwork, unrotated, in the same depth layer
- Movement and observed existing attack state determine facing; idle retains facing. Freeze stops pose and facing. Motion off selects a static directional idle frame
- A display clock advances in Main's unpaused `_process`, including town walking. Animation does not drive damage or simulation
- Foreground draws projectiles/statuses/labels/feedback, but never the hero body. Labels use silhouette-top anchors; culling uses measured visual bounds plus the actual shadow bounds
- Missing resources fall back safely. A process launched before assets existed must restart to observe assets; missing-asset caches are not a hot-reload API

## Focused checks

`bash tools/validate.sh res://tests/retained_actor_layer_test.gd res://tests/retained_visibility_test.gd res://tests/actor_sprite_depth_test.gd res://tests/actor_depth_main_test.gd res://tests/actor_atlas_resources_test.gd`

- Retained lifecycle: 184 passed
- Visibility and real fallback canvas-command bounds: 6,502 passed, including 928 geometry cases
- Atlas/depth/facing/freeze/town-clock contract: 329 passed
- Actual Main wiring and read-only presentation: 13 passed
- Real production atlas/import resources: 886 passed, including all 288 frames
- Total: 7,914 passed, zero failures
- Isolated 30-frame headless Main startup passed
- Six new PNG import configurations use mipmaps and alpha-border fixing; imported atlas Images contain mipmap data
- A 100-monster/120-sync fixture preserves root/part identities, shared texture count, and authoritative/RNG bytes. This is a stability check, not a frame-rate benchmark

One resource-test draft compared JSON float arrays directly with integer arrays. Explicit Rect2i normalization fixed the assertion; all measured alpha bounds then matched exactly. No PNG or production renderer change was needed for that test correction. The original, unmodified process log is preserved as `resources-array-type-attempt01.txt` (886 checks, 288 type-comparison assertion failures). The draft source was edited in place and was not separately preserved; the failed assertion was `declared == [bounds.position.x, bounds.position.y, bounds.end.x, bounds.end.y]`. This log is copied from the original temporary validation output, not transcribed from chat.

## Scope limits

The headless checks do not claim native graphical acceptance or measured render performance. Root owns native Main screenshots. No Windows export, historical aggregate regression, or long soak was run.

Evidence: `result.json`, `final-focused.txt`, `resources-final.txt`, `final-start.txt`.

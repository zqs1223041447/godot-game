# v106 monster-family delta validation

Baseline: `e2fa6db67fb9c4c7f201c795df12bdeb9b699832` (published v105). Godot `4.6.3.stable.official.7d41c59c4`.

## Result

- 2,359 effective source/raw-pixel checks and 2,307 Godot runtime checks passed: **4,666 new checks, zero unresolved failures**
- The already accepted v105 actor/depth 7,914 checks are reused, not rerun
- Exactly one formal headless editor import completed with exit 0 and no `SCRIPT ERROR` / `ERROR`
- One isolated, 30-frame real Main startup completed with exit 0 and `godot-game: playable arena ready`

## Narrow coverage

- All eleven authored templates map to the expected crawler/skitter/brute/rift_warden family; unknown templates use the original vector fallback
- Three new RGBA atlases contain 432 frames with real transparency, antialiased alpha, nonempty silhouettes and transparent padding on every edge; every frame's index, direction, clip and local frame agree with the render manifest
- Every new frame's raw and imported alpha bounds agree with its manifest; PNG SHA256s agree with render records
- All four families use eight directions, eighteen frames per direction and their manifest foot anchors. Catalog head and culling bounds follow the real alpha-pixel unions, including the foot shadow. Offscreen-foot visibility and complete-silhouette exit are tested per family
- The three new imported Images contain actual mipmaps, and their sidecars enable `mipmaps/generate` and `process/fix_alpha_border`. The actor retains linear-with-mipmaps filtering
- 100 mixed-template monsters retain exactly four distinct shared family textures, stable root/body/limb identities over 120 movement syncs and input reversal, and family-specific head anchors
- Runtime checks compare `var_to_bytes` before/after visual synchronization, preserving actual typed Array/Dictionary data, not JSON-normalized values. Global RNG remains untouched. Existing hurt state still reaches the tint key and clears correctly
- Variant tints remain opaque and bounded to RGB <= 1, without emissive brightening. Hurt feedback remains enabled
- Every preexisting source in scripts/data/scenes/project, except the two authorized visual files, is byte-identical to baseline. Existing hero/crawler assets and import sidecars are unchanged. The authorized visual delta is confined to family definitions/mapping/tint; frame selection, resource/bounds/fallback logic and other Actor behavior are unchanged

## Measured family geometry

| Family | Foot pixel | Scale | Alpha union, exclusive right/bottom | Head Y, world |
|---|---:|---:|---:|---:|
| crawler | 64,142 | 0.64 | 3,80,125,183 | -39.68 |
| skitter | 64,142 | 0.5 | 7,80,120,187 | -31 |
| brute | 64,158 | 0.729167 | 5,62,123,185 | -70.00003 |
| rift_warden | 64,158 | 0.72 | 7,29,121,186 | -92.88 |

## First failure and affected-only retry

The first complete Python audit ran 2,359 checks and reported 144 failures, all from a test-only assumption that every render manifest named its local frame field `frame`. Rift Warden's original render schema names it `animation_frame`. Its actual indices, clip ranges, pixels, bounds and SHA were correct. The tests now accept either field without altering the PNG, manifest or production renderer. Only the affected Rift Warden resource audit was repeated: 584 checks, zero failures. Godot runtime checks had not yet run before this correction; their first execution passed all 2,307 checks.

The original failure is retained in `source-pixels-attempt01.txt` and `.json`, with exact source snapshots under `attempt01-sources/`. The corrected Python source is under `retry-sources/`; the first runtime source is under `runtime-attempt01-sources/`. `source-pixels-final.json` explicitly combines unaffected first-attempt evidence with the affected-only retry. Its 2,359 checks are effective unique checks, not the sum of repeated attempts.

## Evidence and reproduction

- `result.json`: concise result, resource measurements, input SHA256s and limits
- `source-pixels-attempt01.*`, `rift-source-pixels-retry.*`, `source-pixels-final.json`: raw pixel and immutable-source audit
- `runtime-attempt01.*`: actual Godot runtime result and log
- `import-attempt01.*`: the single formal import process log and exit status
- `main-short-start.*`: isolated real Main startup log and exit status

Current narrow test commands, after resources are imported:

```sh
python3 tests/monster_family_source_v106_test.py --out /tmp/v106-source-pixels.json
# Set XDG_DATA_HOME, XDG_CONFIG_HOME and XDG_CACHE_HOME to isolated temporary directories.
V106_QA_REPORT=/tmp/v106-runtime.json godot --headless --path . --script res://tests/monster_family_atlas_v106_test.gd
godot --headless --path . --quit-after 30
```

The import generated untracked sidecars for older tracked scripts and screenshot assets. Only those newly generated sidecars were removed; the three new production atlas import files and new runtime test UID are retained. The cleanup list is recorded separately. Existing tracked files were not deleted or rewritten.

## Limits

This is headless resource/lifecycle/authority acceptance, not native graphical or frame-rate acceptance. Root owns native Main screenshots and visual review. No 600-second soak, historical aggregate suite, Windows export, packaging, commit or push was performed.

## Final hero-hurt restoration

After the complete family delta validation, root restored the hero-only hurt branch to the exact v105 full flash color `Color(1.22,1.13,1.02)`. Enemy family hurt feedback still uses the identical 75% blend, and the normal hero/monster tints are unchanged. Five narrowly scoped static assertions verify the exact authorized line, an inverse SHA256 proving there is no other Actor change, and the hero/enemy/non-hurt branches. A single `--check-only` dependency parse of `actor_visual.gd` passed with exit 0 and no errors. No Main was instantiated, and neither the 4,666 checks, formal import nor 30-frame startup was rerun.

`hero-hurt-postcheck.json` and `hero-hurt-dependency-parse.*` record this delta. `result.json` and `source-pixels-final.json` carry the updated final source hash and provenance; earlier attempt logs remain unmodified. The Python source gate's expected tint line was updated for future reproducibility, with the final assertion source preserved separately.

# Sunlit ruins environment study — source and license record

Actual authored meshes and photographed PBR materials from Poly Haven. This is a reproducible Blender environment study, not a concept image or a screenshot of the published game.

## License

All listed asset data are released by Poly Haven under CC0 1.0. The official license explicitly permits commercial use, modification, and redistribution of asset files. Credit is optional, but preserved here for provenance. No account, purchase, subscription, or paid asset was used.

- Official asset license: https://polyhaven.com/license
- CC0 text: https://creativecommons.org/publicdomain/zero/1.0/
- Public API terms: https://github.com/Poly-Haven/Public-API/blob/master/ToS.md
- Sources checked and files retrieved: 2026-10-07 UTC

The website text, site graphics, and example renders are separate from the CC0 assets. No Poly Haven example render is used in the delivered image. The delivered image was rendered locally from the actual meshes and materials.

## Assets and use

| Asset | Author credit | Use |
| --- | --- | --- |
| [Modular Fort 01](https://polyhaven.com/a/modular_fort_01) | Rico Cilliers | Authored arch, wall returns, end buttress and derived fallen masonry |
| [Fern 02](https://polyhaven.com/a/fern_02) | Rico Cilliers (modeling), Rob Tuytel (scanning) | Four source fern-clump variants around edges and wall roots |
| [Rock Moss Set 01](https://polyhaven.com/a/rock_moss_set_01) | Kless Gyzen | Scanned framing rocks and smaller fallen stones |
| [Forest Ground 04](https://polyhaven.com/a/forest_ground_04) | Rob Tuytel (photography/processing), Rico Cilliers (minor adjustment) | Soil and gravel-rich ground blend |
| [Aerial Grass Rock](https://polyhaven.com/a/aerial_grass_rock) | Rob Tuytel | Low-contrast grass/moss bank blend |
| [Medieval Blocks 05](https://polyhaven.com/a/medieval_blocks_05) | Rob Tuytel | Only the localized worn approach to the gate |
| [Grass Bermuda 01](https://polyhaven.com/a/grass_bermuda_01) | Rico Cilliers | Authored blades in selected uneven banks, not uniform full-screen scatter |
| [Shrub 02](https://polyhaven.com/a/shrub_02) | Rico Cilliers | Sparse edge shrubs and wall-root cover |
| [Tree Small 02](https://polyhaven.com/a/tree_small_02) | Rico Cilliers | Two edge tree/branch framing groups, with a bounded subset of original leaf geometry |

## Download and integrity

- Total asset data actually retrieved: 40,094,211 bytes (38.24 MiB). API metadata is not counted in this total.
- All texture files used are 1K. Only the small sets above were downloaded, not a full forest collection.
- Whole asset files were checked against the MD5 values supplied by the official file API. Full per-file URLs, byte counts, and hashes are in `asset-download-audit.json`.
- The original Tree Small 02 glTF buffer is about 95 MB. To keep the working set bounded, its official download endpoint was read using supported HTTP 206 byte ranges. The retained buffer contains the original trunk and branches, plus 120,000 original leaf triangles. This downloaded 9,545,002 bytes of geometry. Each range has its returned Content-Range and SHA-256 recorded in the audit.
- Those leaf pieces are instanced around the single original trunk to form the edge canopy. This is an edited subset of the CC0 model, not the unmodified full tree. The partial buffer cannot be verified against the full original file's MD5; it is identified by the recorded source ranges and local hashes instead.
- Large pine and full-tree packages were inspected through metadata and were not downloaded.
- No downloaded executable or asset script was run. The asset exchange format used was glTF. Blender was launched with `--disable-autoexec`.

## Changes made in this study

The arch uses the authored gate mesh with nonuniform world-scale adjustment and several destructive crown cuts. Walls and plant/rock placements are intentionally composed for this single camera. Fallen masonry uses the same authored stone kit. Terrain geometry, layer masks, sunlight, sky fill, color grading, and composition are new work for this study. The floor is a blended soil/grass/gravel surface with a local old path, not mirrored stone tiles.

The original glTF source modules remain reusable. The scene's packed materials and mesh instances can be inspected in Blender. This study has not been optimized into Godot's final runtime draw-call/LOD budget, baked into an atlas, integrated with collision, or tested in the published game.

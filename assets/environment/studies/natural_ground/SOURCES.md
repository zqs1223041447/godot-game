# Ground texture sources

All three original 1024×1024 RGB diffuse JPEGs were already acquired and verified in the v108 professional-environment work. This branch copies those same bytes; there were no new downloads and no changes to their pixels. Individual byte counts, SHA-256, MD5, original download URLs and match results are in `sources.json`.

- [Forest Ground 04](https://polyhaven.com/a/forest_ground_04): Rob Tuytel; minor adjustment by Rico Cilliers
- [Aerial Grass Rock](https://polyhaven.com/a/aerial_grass_rock): Rob Tuytel
- [Medieval Blocks 05](https://polyhaven.com/a/medieval_blocks_05): Rob Tuytel

Asset data is [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/), as recorded in the [Poly Haven asset license](https://polyhaven.com/license) and the already-backed-up audit at `art-studies/v111/source/provenance/asset-download-audit.json`. The three files total 2,433,844 bytes (2.321 MiB). They are material textures, not website preview images or rendered scene screenshots.

The local shader, fixed mask and authored blending are project work. Only diffuse textures are used. Source orientation remains fixed; the shader's Y sign converts the source horizontal-ground axis into Godot's downward world axis. Textures are not randomly rotated or mirrored. No new normal/roughness/light system is introduced. Source image hashes are preserved even though shader color adjustments and compositing change the final displayed colors.

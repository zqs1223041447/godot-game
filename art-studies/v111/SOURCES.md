# Sources and license

This small derivative uses already-downloaded Poly Haven CC0 asset data and the existing authored v108 Blender scene. No new asset, executable, or texture was downloaded for this continuation. No Poly Haven website preview render is used.

## Source assets

| Asset | Original author | Use in this sample |
| --- | --- | --- |
| [Modular Fort 01](https://polyhaven.com/a/modular_fort_01) | Rico Cilliers | `modular_fort_01_wall_thin_straight_03` short wall; authored/cut `modular_fort_01_wall_thin_gate_01` arch, split walkable sill |
| [Rock Moss Set 01](https://polyhaven.com/a/rock_moss_set_01) | Kless Gyzen | `rock_moss_set_01_rock01` scanned rock |
| [Forest Ground 04](https://polyhaven.com/a/forest_ground_04) | Rob Tuytel; minor adjustment Rico Cilliers | Ground-only assembly-check render |
| [Aerial Grass Rock](https://polyhaven.com/a/aerial_grass_rock) | Rob Tuytel | Ground-only assembly-check render |
| [Medieval Blocks 05](https://polyhaven.com/a/medieval_blocks_05) | Rob Tuytel | Local path within the ground-only assembly-check render |

Poly Haven distributes its asset data under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/); see the [official asset-license page](https://polyhaven.com/license). Asset data may be modified and redistributed, including commercially. Credit is retained for provenance. Website text, logos, and demonstration renders are not included.

Existing retrieval and source verification were recorded on 2026-10-07 UTC in the original v108 working scene. The archived source documents are retained as [`source/provenance/SOURCES.md`](source/provenance/SOURCES.md) and [`source/provenance/asset-download-audit.json`](source/provenance/asset-download-audit.json). The source assets were checked against official file-API records there; this continuation relies on those already-acquired bytes and does not claim a new download or license recheck.

## Derivative changes

- Preserve source orientation, scale, original materials, 55-degree orthographic camera and original sunlight
- Bake each original source transform into its mesh, then translate its physical ground foot to local zero
- Separate the arch's original low sill into a ground-only visual part, with a two-leg blocker instead of a solid gate rectangle
- Render each module independently to transparent RGBA; export its own flat-ground shadow decal without neighbors or old terrain
- Normalize neutral shadow PNG output and assemble the actual renders in a small Godot sample

No proprietary character ZIP, paid library, AI-generated substitute, or unverified third-party asset is part of this package. Project scripts, layout, collision extraction and QA are locally authored for this work. CC0 provenance for the source data does not claim endorsement by the original artists or Poly Haven.

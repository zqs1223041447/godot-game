# Ground dressing source and license record

Only already-acquired, actual Poly Haven asset data from the frozen packed v108 Blender source is used. No website example render, AI substitute, paid character library, or new download is included.

| Source asset | Original author credit | Exact derivative use |
| --- | --- | --- |
| [Fern 02](https://polyhaven.com/a/fern_02) | Rico Cilliers (modeling), Rob Tuytel (scanning) | `fern_02_d`, copied from `Fern cluster 01 / 04`; native source mesh uniformly scaled 1.10× and fixed at its authored output orientation |
| [Rock Moss Set 01](https://polyhaven.com/a/rock_moss_set_01) | Kless Gyzen | `rock_moss_set_01_rock03` and `rock_moss_set_01_rock05`, copied from `Loose scanned rubble 02` and `04`; three fixed small instances with maximum heights 0.12m, 0.09m and 0.08m |

These asset data are [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/), under the [Poly Haven asset-license statement](https://polyhaven.com/license). Modification and redistribution, including commercial use, are permitted by CC0. Credits are retained for provenance, without implying endorsement.

The original source and file-download verification were recorded on 2026-10-07 UTC in `../v108-professional-environment/SOURCES.md` and `asset-download-audit.json`. This work reuses those verified existing bytes; it does not claim a new download or fresh legal review. The packed source SHA-256 is `b9f9ec71ff24d593bbe85b6294aeca24e2d0ca86ddea6370206bb2bdb127ffd7`.

The existing `tree_small_02` branch source was inspected but is not used in this deliverable. There is no grass-field scatter, new shrub, extra fern variant or branch extraction.

## Changes in this derivative

- Preserve actual mesh topology, UVs, original packed materials and existing material grading
- Resize the explicitly selected assets to low decorative proportions, fix their internal composition, and normalize one shared module ground foot
- Preserve v111's 55-degree orthographic projection, 27m view width, original sun direction and original AgX/exposure
- Render each isolated module once for its sprite and once for its own flat-ground shadow
- Set only shadow RGB to exact neutral black while preserving its raw alpha
- Add placement metadata, reproducible scripts and a technical assembly of the real rendered PNGs

The technical assembly additionally shows unchanged v111 wall, arch, moss rock and ground renders solely as scale/placement context. Their source attribution remains in `../v111-modular-environment/SOURCES.md`: Modular Fort 01 by Rico Cilliers; Rock Moss Set 01 by Kless Gyzen; Forest Ground 04 by Rob Tuytel with minor adjustment by Rico Cilliers; Aerial Grass Rock and Medieval Blocks 05 by Rob Tuytel. Those reference textures are not duplicated into this package's production exports.

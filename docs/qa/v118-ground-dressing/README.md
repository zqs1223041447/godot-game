# v118: sparse native-garden ground dressing

Base: `2b751ff9f31322cc72556e74ad96b76aaecf6cae`.
Independent source branch: `codex/v118-ground-dressing`.

Only 遗迹庭园 receives the approved five placements: three low ferns and two
three-pebble groups. The existing four maps and the historical study adapter
receive none. The four PNGs are the approved Poly Haven-derived CC0 exports;
see [original source/license record](../../../art-studies/v118/SOURCES.md).

## Runtime contract

- Read `art-studies/v118/exports/manifest.json` and its fixed
  `qa/example-layout.json`; never generate random placement or orientation
- `world_foot = admitted study_origin + foot_screen_pixel /0.65`
- Sprite offset is `-foot_local_pixel /0.65`; sprite scale is `1/0.65` once
- Five shared-foot shadow anchors precede five decoration anchors in one
  unsorted ground subtree, at absolute z=-1. It follows the opaque ground and
  original module-ground shadows, below the z0 actors, monsters, raised props
  and foreground/drop pass. No foreground/Y-sort occlusion pass is used
- The same four image resources are shared by all ten sprites. Source hashes,
  formats and dimensions are checked before any visible partial arrangement
- Geometry, navigation, collision, saves, actor data and RNG are not changed
- The retained layer has no process/physics callback. Repeated geometry refresh
  or camera motion keeps the same nodes, textures and single build
- Map switching disposes the complete subtree and its four image resources
- Resource failure leaves the optional decoration absent and reports its reason
  in the prop manager; it cannot create partial collision or change entry fees

Only two production files change: the existing prop manager adds this explicit
new-map presentation dispatch/cleanup, and a small retained dressing layer owns
validated resources and fixed placements. No physics, navigation, economy,
progression, old-map definition or character default is changed.

## Focused check

`tests/ruins_garden_dressing_test.gd`: **60 checks,zero failures,exit0**.
Godot4.6.3, one actual native-map entry, existing imported caches, isolated
`/tmp/godot-m1-v118-dressing/{data,config,cache}`.

The check covers resource hashes/dimensions, exact five feet and single scale
conversion, fixed orientations,4 shared images/10 sprites, ground layer order,
no collision/navigation descendants, exact unchanged native contours, no
state/save/gameplay or global-RNG mutation during display refresh, no rebuild
on repeated refresh/camera motion, real town-switch disposal (including weak
texture-reference release), and no dressing on any of the original four maps.

No migration suite,174/575-entry series,600-second run, combat completion,
asset rendering, resource download or Windows export was performed. This is
not a performance benchmark or an all-drop/all-camera gameplay visibility test.

## Native visual review

A separate normal-menu review at21:40–21:41 UTC entered 遗迹庭园 and checked the
actual map. All five low decorations were clear but restrained, route space
remained open and shadows stayed grounded. The single [final game screenshot](native-map.png)
records that view; no additional screenshot or render was requested or made.

## Preserved source package

`art-studies/v118` is a byte-identical copy of the approved27-file package:
6,313,217 bytes, including the packed two-module derived Blender source,
original four raw renders, exports, license/provenance, scripts and technical
QA composites. It does not duplicate the v111 three-module Blender model or
copy any pending character ZIP. The inherited `art-studies/.gdignore` prevents
Godot from importing archived Blender/QA sources.

The authored scripts and relative source-location records remain unchanged.
Their original art-workspace v108/v111 paths are historical provenance, not a
claim that the archive is a standalone fresh-clone rerender command. The packed
derived `source/ground-dressing.blend` is included; `BATCH_COMPLETE.json` keeps
the original single-batch protection. No script was rerun during integration.

`source-copy-manifest.json` records copied bytes/hashes; `tested-inputs.json`
records runtime source and resource hashes. The original failed-run-free log,
exit code and machine-readable60-check result are retained.

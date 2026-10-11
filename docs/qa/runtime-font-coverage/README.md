# Runtime font coverage repair

Verified in the dot Linux checkout, Godot 4.6.3, 2026-10-10 UTC.

## Change

The runtime audit identified 18 uncovered glyphs. The installed Noto Sans CJK SC source at `/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc` exactly matches the existing manifest SHA-256 and SIL Open Font License 1.1. The existing verified subset generator adds 16 missing glyphs without downloading fonts. Only the unavailable disclosure triangles `▾` / `▸` are replaced with the already-bundled `−` / `+`; the adjacent 收起 / 展开 labels remain explicit.

Map/boss names, authored descriptions, gameplay, models, stats, saves, and telegraph rendering are unchanged. The font grows from 705,152 to 710,380 bytes. All 1,671 previously mapped glyph outlines/advances and global layout metrics are unchanged, including the frozen 874-character baseline. License and font-family identity remain unchanged.

## Evidence

- `before.log`: prior audit, 18 uncovered glyphs
- `generation.json`, `after.log`: verified same-source regeneration; coverage passes with 1,687 mapped glyphs
- `retained-glyphs.log`: all previously mapped glyphs preserved, not merely the frozen baseline
- `native-tests.log`: all 22 Python tests pass; isolated Godot headless probe passes 3,368 native mappings and 3,112 Han raster checks at 16/19 px with one font RID and system fallback disabled
- `map-labels.log`: new bounded disclosure regression, 127 checks / zero failures across all five maps and repeated expansion/collapse; canonical authority/save/RNG unchanged
- `map-description.log` / `.json`: existing broader map-description test, 90 checks / one failure at its simulated pointer/prepare transaction in headless mode; not counted as passing

The native probe now includes current runtime strings in its rendering corpus instead of assuming all post-baseline Han glyphs come from the pinned crafting planner. Candidate character sets are cached to keep the expanded corpus bounded in cost.

Two pre-existing same-source unsupported symbols (`⌁`, `◈`) remain documented fallback exceptions. The normal checker passes; strict-symbol mode deliberately remains failing. No windowed screenshot or Windows verification was performed. Headless native mapping/raster validation does not establish visual layout quality.

## Reproduce

```sh
python3 tools/subset_font.py /usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc
python3 tools/check_font_coverage.py
python3 tests/test_font_coverage.py --godot godot
XDG_DATA_HOME=$(mktemp -d /tmp/godot-map-notes-font-XXXXXX) timeout 30s godot --headless --path . --script res://tests/map_notes_font_labels_test.gd
```

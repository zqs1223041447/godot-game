#!/usr/bin/env python3
"""Reject opaque inventory item artwork; complements in-game edge inspection."""
from pathlib import Path
from PIL import Image
import json
import sys
ROOT = Path(__file__).resolve().parents[1]
paths = sorted((ROOT / 'assets/art/equipment').glob('*.png'))
manifest = json.loads((ROOT / 'assets/ui/grimoire/asset_manifest.json').read_text())
paths += [ROOT / a['path'] for a in manifest['assets'] if Path(a['path']).name not in {'parchment.png', 'leather.png'}]
failed = []
for path in paths:
    with Image.open(path) as source:
        if 'A' not in source.getbands():
            failed.append((str(path.relative_to(ROOT)), 'missing alpha channel'))
            continue
        alpha = source.getchannel('A')
        histogram = alpha.histogram()
        clear = sum(histogram[:8]) / (source.width * source.height)
        opaque = sum(histogram[128:]) / (source.width * source.height)
        if clear < 0.05 or opaque < 0.01:
            failed.append((str(path.relative_to(ROOT)), f'clear={clear:.3f}, subject={opaque:.3f}'))
        w,h = source.size
        corners = [alpha.getpixel(p) for p in [(0,0),(w-1,0),(0,h-1),(w-1,h-1)]]
        if any(a > 16 for a in corners):
            failed.append((str(path.relative_to(ROOT)), f'opaque corner {corners}'))
print(f'Item transparency: {len(paths)} assets checked, {len(failed)} failures')
for path, reason in failed:
    print(path, reason)
sys.exit(bool(failed))

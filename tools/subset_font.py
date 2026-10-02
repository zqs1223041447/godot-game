#!/usr/bin/env python3
"""Optional developer tool: regenerate the shipped font after adding UI text.
Requires fontTools; existing bundled font is enough to run/export the game.
Usage: python tools/subset_font.py /path/to/NotoSansCJK-Regular.ttc
"""
from pathlib import Path
import argparse
from fontTools import subset
from fontTools.ttLib import TTFont

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('source', type=Path)
parser.add_argument('--font-number', type=int, default=2, help='SC index in Noto CJK TTC')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
text = ''.join(chr(i) for i in range(32, 127)) + '−—–×◈●· /'
for folder in ('scripts', 'scenes'):
    for path in (root / folder).glob('**/*'):
        if path.suffix in ('.gd', '.tscn'):
            text += path.read_text(encoding='utf-8')
balance = root / 'data' / 'passive_balance.json'
if balance.exists():
    text += balance.read_text(encoding='utf-8')
font = TTFont(args.source, fontNumber=args.font_number)
options = subset.Options()
options.name_IDs = ['*']
options.name_legacy = True
options.name_languages = ['*']
subsetter = subset.Subsetter(options=options)
subsetter.populate(text=text)
subsetter.subset(font)
# Distinct family name makes this modified subset clear to font consumers.
for record in font['name'].names:
    if record.nameID in (1, 4, 6, 16):
        name = 'ArenaSansSC-Regular' if record.nameID == 6 else 'Arena Sans SC'
        record.string = name.encode(record.getEncoding(), errors='replace')
out = root / 'assets/fonts/arena_sans.otf'
font.save(out)
print(f'{out}: {out.stat().st_size:,} bytes, {len(set(text))} requested characters')

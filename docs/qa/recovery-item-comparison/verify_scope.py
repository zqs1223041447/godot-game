"""Bounded source/document preservation against the reviewed pre-change main."""
import hashlib
import json
import re
import subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
BASE = '818b9a395b9a461e63f45fa8bfeb2ec71d316dd1'
def old(path):
    return subprocess.check_output(['git', 'show', f'{BASE}:{path}'], cwd=ROOT)
def cards(text):
    return dict(re.findall(r'<article\b[^>]*\bid="([^"]+)"[^>]*>(.*?)</article>', text, re.S))
current = (ROOT / 'docs/reference/index.html').read_text()
a = cards(old('docs/reference/index.html').decode()); b = cards(current)
assert a and a.keys() == b.keys()
changed = [key for key in a if a[key] != b[key]]
assert changed == ['rules-ownership'], changed
assert '待安置物品也可悬停查看完整详情' in b['rules-ownership']
ids = set(re.findall(r'\bid="([^"]+)"', current))
links = re.findall(r'href="#([^"]+)"', current)
assert all(link in ids for link in links)
paths = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', BASE, '--', 'scripts', 'assets', 'data', 'scenes', 'project.godot'], cwd=ROOT, text=True).splitlines()
changed_runtime = [p for p in paths if old(p) != (ROOT / p).read_bytes()]
assert changed_runtime == ['scripts/ui/canonical_inventory_panel.gd'], changed_runtime
assert old('docs/reference/catalog.json') == (ROOT / 'docs/reference/catalog.json').read_bytes()
# Shared UI/data/transactions are reused byte-for-byte. Only pending controls changed.
ui = (ROOT / changed_runtime[0]).read_text()
previous = old(changed_runtime[0]).decode()
assert ui[ui.index('func _move_requested'):ui.index('func _hover_pending')] == previous[previous.index('func _move_requested'):previous.index('func _hover_equipment')]
from fontTools.ttLib import TTFont
font = TTFont(ROOT / 'assets/fonts/arena_sans.otf')
covered = set().union(*(t.cmap.keys() for t in font['cmap'].tables))
new_text = '待安置 件 · 悬停详情 · Shift 对比腾出空间后点击取回'
assert all(ord(c) in covered for c in new_text if not c.isspace())
report = {'baseline': BASE, 'changed_runtime': changed_runtime, 'unchanged_runtime_assets': len(paths)-1,
          'catalog_byte_identical': True, 'cards': len(a), 'changed_cards': changed,
          'unchanged_cards': len(a)-1, 'valid_internal_links': len(links),
          'original_move_activate_methods_byte_identical': True, 'new_ui_text_font_coverage': True,
          'failures': 0}
(ROOT / 'docs/qa/recovery-item-comparison/preservation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
print(json.dumps(report, ensure_ascii=False, indent=2))

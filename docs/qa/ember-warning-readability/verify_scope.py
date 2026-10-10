"""Bounded source/document preservation against the reviewed pre-change main."""
import hashlib
import json
import re
import subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
BASE = 'b4bbb2502dc85a7ba26b699534890b315a4ca668'
def old(path):
    return subprocess.check_output(['git', 'show', f'{BASE}:{path}'], cwd=ROOT)
def cards(text):
    return dict(re.findall(r'<article\b[^>]*\bid="([^"]+)"[^>]*>(.*?)</article>', text, re.S))
current = (ROOT / 'docs/reference/index.html').read_text()
a = cards(old('docs/reference/index.html').decode()); b = cards(current)
assert a and a.keys() == b.keys()
changed = [key for key in a if a[key] != b[key]]
assert changed == ['monster_attacks-locked_circle'], changed
assert '灰烬守卫的蓄力火纹位于重击圆内下方' in b['monster_attacks-locked_circle']
ids = set(re.findall(r'\bid="([^"]+)"', current))
links = re.findall(r'href="#([^"]+)"', current)
assert all(link in ids for link in links)
paths = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', BASE, '--', 'scripts', 'assets', 'data', 'scenes', 'project.godot'], cwd=ROOT, text=True).splitlines()
changed_runtime = [p for p in paths if old(p) != (ROOT / p).read_bytes()]
assert changed_runtime == ['scripts/visuals/telegraph_renderer.gd'], changed_runtime
assert old('docs/reference/catalog.json') == (ROOT / 'docs/reference/catalog.json').read_bytes()
# Existing input filtering, counts, draw submission and other shapes remain intact.
ui = (ROOT / changed_runtime[0]).read_text()
previous = old(changed_runtime[0]).decode()
assert ui[:ui.index('static func _append_state')] == previous[:previous.index('static func _append_state')]
assert ui[ui.index('static func _append_annulus'):] == previous[previous.index('static func _append_annulus'):]
baseline_report=json.loads((ROOT / 'docs/qa/ember-warning-readability/baseline/report.json').read_text())
after_report=json.loads((ROOT / 'docs/qa/ember-warning-readability/after/report.json').read_text())
assert len(baseline_report['frames'])==len(after_report['frames'])==4
for before,after in zip(baseline_report['frames'],after_report['frames']):
    assert before['label']==after['label'] and before['states']==after['states'] and before['trace']==after['trace']
    assert len(before['primitives'])==len(after['primitives'])
    for x,y in zip(before['primitives'],after['primitives']):
        if x['role'] not in ['rune_base','rune_charge']:assert x==y
from fontTools.ttLib import TTFont
font = TTFont(ROOT / 'assets/fonts/arena_sans.otf')
covered = set().union(*(t.cmap.keys() for t in font['cmap'].tables))
new_text = '灰烬守卫的蓄力火纹位于重击圆内下方，避开圆心角色与头顶文字；深色底线上的米色线条随原蓄力进度逐渐完成，低特效也保留。圆周始终表示完整伤害范围，火纹不是缩小的伤害区；落击后按原恢复期变灰消退。'
assert all(ord(c) in covered for c in new_text if not c.isspace())
report = {'baseline': BASE, 'changed_runtime': changed_runtime, 'unchanged_runtime_assets': len(paths)-1,
          'catalog_byte_identical': True, 'cards': len(a), 'changed_cards': changed,
          'unchanged_cards': len(a)-1, 'valid_internal_links': len(links),
          'captured_attack_states_and_events_identical': True, 'primitive_counts_and_non_rune_art_identical': True, 'input_and_draw_and_annulus_methods_identical': True, 'new_ui_text_font_coverage': True,
          'failures': 0}
(ROOT / 'docs/qa/ember-warning-readability/preservation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
print(json.dumps(report, ensure_ascii=False, indent=2))

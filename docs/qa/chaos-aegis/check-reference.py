#!/usr/bin/env python3
"""Bounded catalog/card delta and runtime glyph checks against the accepted baseline."""
import copy
import hashlib
import json
import re
import subprocess
from pathlib import Path
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[3]
QA = ROOT / 'docs/qa/chaos-aegis'
BASELINE = 'f5abdf8bed36c02a14ef778edf8dd81ce52345e0'


def old(path):
    return subprocess.check_output(['git', 'show', BASELINE + ':' + path], cwd=ROOT, text=True)


catalog = json.loads((ROOT / 'docs/reference/catalog.json').read_text())
fragment = json.loads((QA / 'reference-fragment.json').read_text())
assert catalog['town_maps']['chaos_aegis'] == fragment
assert fragment['integration_status'] == 'implemented' and fragment['save_version'] == 59
assert fragment['options']['normal']['completion_reward_bonus'] == 2
assert fragment['options']['test']['completion_reward_bonus'] == 0
assert all(tiers == [2, 3] for tiers in fragment['eligible_tiers'].values())
assert fragment['examples']['crawler']['after_components']['chaos'] == 80
assert abs(fragment['examples']['chaos_guard']['after_components']['chaos'] - 55) < 1e-9
assert [row['effective'] for row in fragment['cap_examples']] == [0, 0.2, 0.45, 0.75, 0.75]
projected = copy.deepcopy(catalog)
del projected['town_maps']['chaos_aegis']
projected['town_maps']['options']['special_modifiers'] = [row for row in projected['town_maps']['options']['special_modifiers'] if row['id'] != 'chaos_aegis']


def remove_new_eligibility(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if key == 'eligible_special_ids':
                value[key] = [entry for entry in child if entry != 'chaos_aegis']
            else:
                remove_new_eligibility(child)
    elif isinstance(value, list):
        for child in value:
            remove_new_eligibility(child)


remove_new_eligibility(projected)
assert projected == json.loads(old('docs/reference/catalog.json')), 'Unrelated historical catalog changed'
pattern = r'(<article\b[^>]*\bid="([^"]+)".*?</article>)'
previous = {key: raw for raw, key in re.findall(pattern, old('docs/reference/index.html'), re.S)}
html = (ROOT / 'docs/reference/index.html').read_text()
current = {key: raw for raw, key in re.findall(pattern, html, re.S)}
assert current.keys() - previous.keys() == {'map_specials-chaos_aegis'}
assert not previous.keys() - current.keys()
changed = [key for key in previous if previous[key] != current[key]]
assert set(changed) == {'maps-' + key for key in fragment['eligible_tiers']}
card = current['map_specials-chaos_aegis']
for text in ['class="status implemented">已实现', '20', '75%', '混沌', '+2', '不增加完成奖励', '不能同时选择']:
    assert text in card, text
for anchor in re.findall(r'href="#([^"]+)"', card):
    assert anchor in current, anchor
font = TTFont(ROOT / 'assets/fonts/arena_sans.otf')
cmap = set().union(*(table.cmap for table in font['cmap'].tables))
runtime_text = fragment['definition']['name'] + fragment['definition']['description']
missing = sorted({letter for letter in runtime_text if not letter.isspace() and ord(letter) not in cmap})
assert not missing, missing
for path, expected in fragment['source_sha256'].items():
    assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == expected, path
report = {'baseline': BASELINE, 'failures': 0, 'new_cards': ['map_specials-chaos_aegis'],
          'changed_cards': changed, 'unrelated_catalog_and_cards_unchanged': True,
          'new_runtime_missing_glyphs': missing}
(QA / 'reference-check.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(report, ensure_ascii=False))

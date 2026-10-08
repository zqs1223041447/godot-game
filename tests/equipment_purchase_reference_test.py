#!/usr/bin/env python3
"""Verify this narrow documentation delta against the approved gameplay base."""
import hashlib
import importlib.util
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = 'ba2f8c0a1e7528a7a1f8847540665384b7ac41dc'
def baseline(path):
    return subprocess.check_output(['git', 'show', f'{BASE}:{path}'], cwd=ROOT)
spec = importlib.util.spec_from_file_location('reference', ROOT / 'tools/build_reference.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)
span_spec = importlib.util.spec_from_file_location('reference_span', ROOT / 'tools/merge_ruins_garden_reference.py')
span_module = importlib.util.module_from_spec(span_spec)
span_spec.loader.exec_module(span_module)
old_text = baseline('docs/reference/catalog.json').decode()
old = json.loads(old_text)
old_html = baseline('docs/reference/index.html').decode()
current_text = (ROOT / 'docs/reference/catalog.json').read_text()
current = json.loads(current_text)
purchase = current['town_maps'].pop('equipment_purchase')
assert current == old, 'Unrelated catalog semantic change'
for key in old:
    paths = [['town_maps', child] for child in old[key]] if key == 'town_maps' else [[key]]
    for path in paths:
        old_start, old_end = span_module.member_span(old_text, path)
        new_start, new_end = span_module.member_span(current_text, path)
        assert old_text[old_start:old_end] == current_text[new_start:new_end], f'Unrelated catalog bytes changed: {path}'
art = json.loads((ROOT / 'docs/reference/art/manifest.json').read_text())
assert builder.build(old, art) == old_html, 'Old input HTML must remain byte-identical'
assert baseline('docs/reference/source-tree-coverage.json') == (ROOT / 'docs/reference/source-tree-coverage.json').read_bytes()
assert not subprocess.check_output(['git','diff','--name-only',BASE,'--','docs/reference/art','assets'],cwd=ROOT)
pattern = r'(<article\b[^>]*id="([^"]+)"[^>]*>.*?</article>)'
def cards(text): return {key: card for card, key in re.findall(pattern, text, re.S)}
before = cards(old_html)
after = cards((ROOT / 'docs/reference/index.html').read_text())
assert before and before.keys() == after.keys()
changed = [key for key in before if before[key] != after[key]]
allowed = {'town_services-'+key for key in ['equipment_merchant','skill_merchant','crafter','jewel_merchant','passive_reset']}
assert set(changed) == allowed, f'Unexpected changed cards: {changed}'
merchant = after['town_services-equipment_merchant']
assert '购买不随机生成词缀' in merchant and '普通无词缀' in merchant
assert f'data-equipment-purchase-field="cost">{purchase["cost"]}</span>' in merchant
assert f'data-equipment-purchase-field="item_level">{purchase["item_level"]}</span>' in merchant
assert len(re.findall('data-base-purchase-id=',merchant)) == len(purchase['offers'])
for row in purchase['offers']:
    assert f'data-base-purchase-id="{row["base_id"]}" data-cost="{row["cost"]}"' in merchant
    assert row['rarity']=='normal' and row['affix_count']==0
for source, digest in purchase['source_sha256'].items():
    assert hashlib.sha256((ROOT/source).read_bytes()).hexdigest()==digest
html = (ROOT / 'docs/reference/index.html').read_text()
ids = set(re.findall(r'\bid="([^"]+)"',html))
links = re.findall(r'href="#([^"]+)"',merchant)
assert all(key in ids for key in links)
report = {'baseline':BASE,'old_data_generator_byte_identical':True,'old_catalog_semantics_preserved':True,
          'old_catalog_value_bytes_preserved':True,
          'source_execution_coverage_byte_identical':True,'art_unchanged':True,'total_cards':len(before),
          'changed_cards':changed,'unchanged_cards':len(before)-len(changed),'catalog_bases':len(purchase['offers']),
          'merchant_internal_links':len(links),'save_version':purchase['save_version'],'source_sha256':purchase['source_sha256']}
(ROOT/'docs/qa/equipment-purchase-reference/preservation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False,indent=2))

#!/usr/bin/env python3
"""Verify the three approved F8 cards and preserve all previous catalog bytes."""
import hashlib
import importlib.util
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = '9b5d618ad7a88e4aed69b1aae37e37ddd2c3bff6'


def baseline(path):
    return subprocess.check_output(['git', 'show', f'{BASE}:{path}'], cwd=ROOT)


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


builder = module('flask_reference_builder', 'tools/build_reference.py')
scanner = module('flask_reference_span', 'tools/merge_ruins_garden_reference.py')
old_text = baseline('docs/reference/catalog.json').decode()
old = json.loads(old_text)
new_text = (ROOT / 'docs/reference/catalog.json').read_text()
new = json.loads(new_text)
purchase = new['town_maps'].pop('flask_purchase')
assert new == old, 'Unrelated catalog semantic changes'
for key in old:
    paths = [['town_maps', child] for child in old[key]] if key == 'town_maps' else [[key]]
    for path in paths:
        a, b = scanner.member_span(old_text, path)
        c, d = scanner.member_span(new_text, path)
        assert old_text[a:b] == new_text[c:d], f'Unrelated catalog bytes changed: {path}'
art = json.loads((ROOT / 'docs/reference/art/manifest.json').read_text())
old_html = baseline('docs/reference/index.html').decode()
assert builder.build(old, art) == old_html, 'Generator changed old-input HTML'
new_html = (ROOT / 'docs/reference/index.html').read_text()
pattern = r'(<article\b[^>]*id="([^"]+)"[^>]*>.*?</article>)'


def cards(text):
    return {key: card for card, key in re.findall(pattern, text, re.S)}


before, after = cards(old_html), cards(new_html)
assert before and before.keys() == after.keys()
changed = [key for key in before if before[key] != after[key]]
allowed = {'town_services-equipment_merchant', 'flasks-life', 'flasks-mana'}
assert set(changed) == allowed, f'Unexpected changed cards: {changed}'


def remove_changed_cards(text):
    return re.sub(pattern, lambda match: '' if match.group(2) in allowed else match.group(1), text, flags=re.S)


payload_pattern = r'<script id="reference-data" type="application/json">(.*?)</script>'
old_payload = json.loads(re.search(payload_pattern, old_html, re.S).group(1))
new_payload = json.loads(re.search(payload_pattern, new_html, re.S).group(1))
assert len(old_payload['records']) == len(new_payload['records'])
search_changes = []
for old_record, new_record in zip(old_payload['records'], new_payload['records']):
    if old_record != new_record:
        assert old_record['id'] in allowed and new_record['id'] == old_record['id']
        assert {key for key in old_record if old_record[key] != new_record[key]} == {'search'}
        search_changes.append(old_record['id'])
assert set(search_changes) == allowed
assert {key: value for key, value in old_payload.items() if key != 'records'} == {key: value for key, value in new_payload.items() if key != 'records'}


def normalize_generated_metadata(text):
    text = re.sub(payload_pattern, '<script id="reference-data">VERIFIED_SEARCH_DATA</script>', text, flags=re.S)
    return re.sub(r'数据指纹 [0-9a-f]{16}', '数据指纹 VERIFIED_DIGEST', text)


for html, catalog in [(old_html, old), (new_html, json.loads(new_text))]:
    digest = hashlib.sha256(json.dumps(catalog, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()).hexdigest()[:16]
    assert '数据指纹 ' + digest in html
assert normalize_generated_metadata(remove_changed_cards(new_html)) == normalize_generated_metadata(remove_changed_cards(old_html)), 'HTML outside approved cards and verified metadata changed'
assert purchase['service_id'] == 'equipment_merchant' and purchase['cost'] == 8 and purchase['save_version'] == 55
assert len(purchase['offers']) == 2
assert {row['definition_id'] for row in purchase['offers']} == {'flask:life', 'flask:mana'}
merchant = after['town_services-equipment_merchant']
assert len(re.findall('data-base-purchase-id=', merchant)) == 15
assert len(re.findall('data-flask-purchase-id=', merchant)) == 2
assert '固定机制装备、药剂、珠宝与免费碎片仍属独立测试供应' not in merchant
assert '15种普通无词缀底材和两种基础生命/魔力药剂' in merchant
assert f'data-flask-purchase-field="cost">{purchase["cost"]}</span>' in merchant
for row in old['town_maps']['equipment_purchase']['offers']:
    assert f'data-base-purchase-id="{row["base_id"]}" data-cost="{row["cost"]}"' in merchant
    assert row['rarity'] == 'normal' and row['affix_count'] == 0 and row['item_level'] == 1
for row in purchase['offers']:
    card = after['flasks-' + row['definition_id'].split(':', 1)[1]]
    assert row['cost'] == 8 and row['size'] == [1, 2] and row['use_cost'] == 10 and row['max_charges'] == 30
    assert row['duration'] == 3 and row['recovery_fraction'] == 0.35
    assert row['resource'] == ('health' if row['definition_id'] == 'flask:life' else 'mana')
    for text in [merchant, card]:
        assert f'data-flask-purchase-id="{row["definition_id"]}" data-cost="8"' in text
        assert all(term in text for term in ['未暂停', '可战斗区域', '同资源', '充能不足', '不返款', '药剂栏'])
    assert builder.lines(row['description']) in merchant
    assert '不自动装备' in card and 'Alt+1至Alt+5' in card and '失败不扣充能' in card
for source, digest in purchase['source_sha256'].items():
    assert hashlib.sha256((ROOT / source).read_bytes()).hexdigest() == digest, source
assert baseline('docs/reference/source-tree-coverage.json') == (ROOT / 'docs/reference/source-tree-coverage.json').read_bytes()
assert not subprocess.check_output(['git', 'diff', '--name-only', BASE, '--', 'docs/reference/art', 'assets', 'scripts'], cwd=ROOT)
ids = set(re.findall(r'\bid="([^"]+)"', new_html))
links = [key for card in allowed for key in re.findall(r'href="#([^"]+)"', after[card])]
assert all(key in ids for key in links), 'Broken internal reference link'
report = {
    'baseline': BASE, 'old_input_html_byte_identical': True,
    'old_catalog_semantics_and_value_bytes_preserved': True,
    'html_outside_approved_cards_and_verified_metadata_byte_identical': True,
    'search_changes_only_in_approved_cards': search_changes,
    'catalog_fingerprint_verified': True,
    'runtime_and_art_unchanged': True, 'execution_coverage_unchanged': True,
    'total_cards': len(before), 'changed_cards': changed, 'unchanged_cards': len(before) - len(changed),
    'equipment_bases': 15, 'flask_offers': 2, 'cost_per_bottle': 8, 'use_charge_cost': 10,
    'internal_links': len(links), 'save_version': purchase['save_version'], 'source_sha256': purchase['source_sha256'],
}
(ROOT / 'docs/qa/flask-purchase-reference/preservation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(report, ensure_ascii=False, indent=2))

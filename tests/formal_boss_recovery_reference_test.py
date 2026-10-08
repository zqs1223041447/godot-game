#!/usr/bin/env python3
"""Check one F8 explanation against the approved runtime baseline, without gameplay."""
import hashlib
import importlib.util
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = 'a2f6f21669c43c037668756e512e9aa32c898923'
KEY = 'formal_boss_equipment_recovery'
CARD = 'rules-exploration_maps'


def baseline(path):
    return subprocess.check_output(['git', 'show', f'{BASE}:{path}'], cwd=ROOT)


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


builder = module('boss_reference_builder', 'tools/build_reference.py')
scanner = module('boss_reference_span', 'tools/merge_ruins_garden_reference.py')
old_text = baseline('docs/reference/catalog.json').decode()
old = json.loads(old_text)
new_text = (ROOT / 'docs/reference/catalog.json').read_text()
new = json.loads(new_text)
note = new['exploration_maps'][KEY]
without_note = json.loads(new_text)
del without_note['exploration_maps'][KEY]
assert without_note == old, 'Only the explanation field may be added'
for key in old:
    paths = [['exploration_maps', child] for child in old[key]] if key == 'exploration_maps' else [[key]]
    for path in paths:
        a, b = scanner.member_span(old_text, path)
        c, d = scanner.member_span(new_text, path)
        assert old_text[a:b] == new_text[c:d], f'Previous value bytes changed: {path}'
doc_path = 'docs/EXPLORATION_MAPS.zh-CN.md'
new_doc = (ROOT / doc_path).read_text()
assert new_doc.count(note) == 1
assert new_doc.replace(note + '\n\n', '', 1) == baseline(doc_path).decode(), 'Gameplay document grew beyond one paragraph'
assert all(term in note for term in ['正式地图首领的稀有装备', '背包放不下', '待安置', '按 I', '尺寸足够的连续空间', '同一实例', 'UID 与词缀保持', '原物品与序号上限不变'])
assert not any(term in note for term in ['绝不丢', '崩溃', '无限', '抗断电'])
art = json.loads((ROOT / 'docs/reference/art/manifest.json').read_text())
old_html = baseline('docs/reference/index.html').decode()
new_html = (ROOT / 'docs/reference/index.html').read_text()
assert builder.build(old, art) == old_html, 'Old-input output must remain byte-identical'
assert builder.build(new, art) == new_html, 'Current checked-in HTML differs from generator'
pattern = r'(<article\b[^>]*id="([^"]+)"[^>]*>.*?</article>)'
before = {key: value for value, key in re.findall(pattern, old_html, re.S)}
after = {key: value for value, key in re.findall(pattern, new_html, re.S)}
assert before and before.keys() == after.keys()
changed = [key for key in before if before[key] != after[key]]
assert changed == [CARD], changed
paragraph = '<p data-boss-equipment-recovery="true">' + builder.esc(note) + '</p>'
assert after[CARD].count(paragraph) == 1
assert after[CARD].replace(paragraph, '', 1) == before[CARD], 'The card changed beyond one paragraph'
payload_pattern = r'<script id="reference-data" type="application/json">(.*?)</script>'
old_payload = json.loads(re.search(payload_pattern, old_html, re.S).group(1))
new_payload = json.loads(re.search(payload_pattern, new_html, re.S).group(1))
assert len(old_payload['records']) == len(new_payload['records'])
search_changes = []
for a, b in zip(old_payload['records'], new_payload['records']):
    if a != b:
        assert a['id'] == b['id'] == CARD
        assert {key for key in a if a[key] != b[key]} == {'search'}
        search_changes.append(a['id'])
assert search_changes == [CARD]
assert {k: v for k, v in old_payload.items() if k != 'records'} == {k: v for k, v in new_payload.items() if k != 'records'}


def normalized(text):
    text = re.sub(pattern, lambda match: '' if match.group(2) == CARD else match.group(1), text, flags=re.S)
    text = re.sub(payload_pattern, '<script id="reference-data">VERIFIED_SEARCH_DATA</script>', text, flags=re.S)
    return re.sub(r'数据指纹 [0-9a-f]{16}', '数据指纹 VERIFIED_DIGEST', text)


assert normalized(new_html) == normalized(old_html), 'Unexpected changes outside approved card/metadata'
for html, data in [(old_html, old), (new_html, new)]:
    digest = hashlib.sha256(json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()).hexdigest()[:16]
    assert '数据指纹 ' + digest in html
ids = set(re.findall(r'\bid="([^"]+)"', new_html))
links = re.findall(r'href="#([^"]+)"', after[CARD])
assert all(key in ids for key in links), 'Broken internal link'
assert not subprocess.check_output(['git', 'diff', '--name-only', BASE, '--', 'scripts', 'assets', 'docs/reference/art', 'docs/reference/originals', 'docs/reference/source-tree-coverage.json'], cwd=ROOT)
hashes = {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in ['tools/build_reference.py', 'scripts/main.gd', 'scripts/canonical_game_state.gd', doc_path]}
for path in ['scripts/main.gd', 'scripts/canonical_game_state.gd']:
    assert baseline(path) == (ROOT / path).read_bytes()
report = {'baseline': BASE, 'note': note, 'old_input_html_byte_identical': True,
          'old_catalog_semantics_and_value_bytes_preserved': True,
          'gameplay_doc_one_paragraph_only': True, 'total_cards': len(before),
          'changed_cards': changed, 'unchanged_cards': len(before) - 1,
          'card_one_paragraph_only': True, 'search_changes': search_changes,
          'outside_card_and_verified_metadata_byte_identical': True,
          'catalog_fingerprints_verified': True, 'internal_links': len(links),
          'runtime_assets_and_execution_coverage_unchanged': True,
          'source_sha256': hashes, 'failures': 0,
          'scope': 'Local documentation checks only; no gameplay/transaction rerun'}
target = ROOT / 'docs/qa/formal-boss-recovery-reference/preservation.json'
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(report, ensure_ascii=False, indent=2))

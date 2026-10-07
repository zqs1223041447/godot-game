#!/usr/bin/env python3
"""Verify current Ginkgo facts and raw preservation without running Godot."""
import ast
import hashlib
from html.parser import HTMLParser
import importlib.util
import json
import math
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[3]
QA = Path(__file__).resolve().parent
REF = ROOT / 'docs/reference'
BASE = 'bdea0872'


def sha(raw): return hashlib.sha256(raw).hexdigest()
def baseline(path): return subprocess.check_output(['git', 'show', BASE + ':' + path], cwd=ROOT)
def load(path): return json.loads(path.read_text())
def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec); spec.loader.exec_module(result); return result


def cards(html):
    return {key: body for body, key in re.findall(r'(<article\b[^>]*\bid="([^"]+)"[^>]*>.*?</article>)', html, re.S)}


class Page(HTMLParser):
    def __init__(self):
        super().__init__(); self.ids = []; self.links = []; self.assets = []; self.values = {}
    def handle_starttag(self, tag, pairs):
        attrs = dict(pairs)
        if 'id' in attrs: self.ids.append(attrs['id'])
        if 'href' in attrs: self.links.append(attrs['href'])
        if 'src' in attrs: self.assets.append(attrs['src'])
        if 'data-ginkgo-inner-outer-value' in attrs:
            key = attrs['data-ginkgo-inner-outer-value']
            assert key not in self.values, key
            self.values[key] = float(attrs['data-value'])


def main():
    merge = module('merge_v101', QA / 'merge-fragment.py')
    builder = module('builder_v101', ROOT / 'tools/build_reference.py')
    before, raw = baseline('docs/reference/catalog.json').decode(), (REF / 'catalog.json').read_text()
    old, data = json.loads(before), json.loads(raw)
    fragment = load(QA / 'ginkgo-inner-outer-fragment.json')
    assert data == merge.expected_data(old, fragment)
    assert data['game_version'] == old['game_version'] and data['save_version'] == old['save_version'] == 53
    a, b = merge.tokens(before), merge.tokens(raw)
    assert {key for key in a if a[key] != b[key]} == {'exploration_maps'}
    assert set(b) - set(a) == {'ginkgo_inner_outer'}
    preserved_top = {key: sha(token.encode()) for key, token in a.items() if b[key] == token}
    # Prove nested siblings, geometry, rosters, old reports, economic values and spellings.
    for segment in ['exploration_maps', 'maps', 'ginkgo_arcade']:
        assert all(a[key] == b[key] for key in a if key != segment)
        a, b = merge.tokens(a[segment]), merge.tokens(b[segment])
    assert {key for key in a if a[key] != b[key]} == {'boss_definition', 'description'}
    assert all(a[key] == b[key] for key in a if key not in ['boss_definition', 'description'])
    html, old_html = (REF / 'index.html').read_text(), baseline('docs/reference/index.html').decode()
    current, previous = cards(html), cards(old_html)
    assert current.keys() == previous.keys()
    changed = {key for key in previous if current[key] != previous[key]}
    assert changed == {'maps-ginkgo_arcade'}, changed
    preserved_cards = {key: sha(body.encode()) for key, body in previous.items() if key not in changed}
    card = current['maps-ginkgo_arcade']
    assert '第一响结束后立即返回原圈仍可能被后续回响命中' not in card
    for term in ['内圈后外环', '空心环', '等号不安全', '名义预算不是保证生命损失', 'v83', 'ginkgo_inner_outer', 'original-ginkgo-inner-outer-v1', 'GINKGO_INNER_OUTER.zh-CN.md']:
        assert term in card, term
    payload_pattern = r'<script id="reference-data" type="application/json">(.*?)</script>'
    def payload(text): return json.loads(re.search(payload_pattern, text, re.S)[1])
    old_payload, new_payload = payload(old_html), payload(html)
    for field in old_payload:
        if field != 'records': assert old_payload[field] == new_payload[field], field
    records = {row['id']: row for row in new_payload['records']}
    old_records = {row['id']: row for row in old_payload['records']}
    assert records.keys() == old_records.keys()
    assert {key for key in records if records[key] != old_records[key]} == changed
    for term in ['内圈', '外环', '130', '240', '115', '255', '1.4', '0.6', '1.9']:
        assert term in records['maps-ginkgo_arcade']['search'], term
    # Outside the single article, its search payload and the overall data fingerprint, the page is exact.
    def strip_allowed(text):
        text = text.replace(cards(text)['maps-ginkgo_arcade'], '<CURRENT_GINKGO>')
        text = re.sub(payload_pattern, '<REFERENCE_PAYLOAD>', text, flags=re.S)
        return re.sub(r'数据指纹 [a-f0-9]{16}', '数据指纹 <DIGEST>', text)
    assert strip_allowed(html) == strip_allowed(old_html)
    page = Page(); page.feed(html)
    assert len(page.ids) == len(set(page.ids))
    for link in page.links:
        if link.startswith('#'): assert link[1:] in page.ids, link
        elif not re.match(r'^[a-z]+:', link): assert (REF / link.split('#')[0]).resolve().is_file(), link
    for asset in page.assets:
        if not re.match(r'^[a-z]+:', asset): assert (REF / asset).is_file(), asset
    rule = data['ginkgo_inner_outer']; boss = data['exploration_maps']['maps']['ginkgo_arcade']['boss_definition']
    profile, second = boss['profile'], boss['second_pulse']
    expected = {'trigger-distance': 240, 'first-windup': 1.4, 'first-radius': 130,
        'second-windup': 1, 'inner-radius': 130, 'outer-radius': 240, 'stage-multiplier': .6,
        'combined-multiplier': 1.2, 'base-recovery': 1.9, 'player-radius': 15,
        'safe-inner-distance': 115, 'safe-outer-distance': 255, 'main-checks': rule['actual_main_checks'],
        'example-first-age': 1.4, 'example-second-age': 2.4,
        'example-scaled-recovery': rule['example_policy']['profile']['recovery_seconds']}
    assert page.values.keys() == expected.keys()
    for key, value in expected.items(): assert math.isclose(page.values[key], value, abs_tol=1e-10), key
    assert profile == {'damage_multiplier': .6, 'radius': 130, 'recovery_seconds': 1.9, 'windup_seconds': 1.4}
    assert second == {'shape': 'annulus', 'inner_radius': 130, 'radius': 240, 'windup_seconds': 1}
    assert boss['pulse_count'] == 2 and boss['pulse_interval'] == 1 and boss['trigger_distance'] == 240
    assert rule['combined_damage_multiplier'] == 2 * profile['damage_multiplier']
    assert rule['safe_inner_distance'] == second['inner_radius'] - rule['player_radius']
    assert rule['safe_outer_distance'] == second['radius'] + rule['player_radius']
    assert rule['profile_id'] == boss['profile_id'] == 'ginkgo_inner_outer'
    assert rule['balance_version'] == boss['balance_version'] == 'original-ginkgo-inner-outer-v1'
    for key in ['actual_main_report', 'actual_main_log', 'actual_main_fixture', 'runtime_tested_inputs', 'current_runtime_report', 'current_runtime_log']:
        item = rule[key]; assert sha((ROOT / item['path']).read_bytes()) == item['sha256'], key
    for path, fingerprint in load(QA / 'export-input-sha256.json').items():
        if path in ['docs/reference/index.html', 'docs/reference/catalog.json']:
            assert sha(baseline(path)) == fingerprint, path
        else:
            assert sha((ROOT / path).read_bytes()) == fingerprint, path
    report = load(ROOT / rule['actual_main_report']['path'])
    assert int(report['failures']) == 0 and int(report['checks']) > 0
    assert int(rule['actual_main_checks']) == int(report['checks'])
    example = report['groups']['held_input_leave_reenter']
    assert rule['example_events'] == example['trace']
    assert rule['example_initial_attack'] == example['initial_attack']
    assert rule['example_outer_snapshot'] == example['outer_snapshot']
    assert rule['example_source'] == report['entries'][0]['boss']
    assert rule['example_policy'] == report['entries'][0]['policy']
    assert not any(event['applied'] for event in rule['example_events'])
    pure = load(ROOT / rule['current_runtime_report']['path'])
    assert pure['checks'] == rule['current_runtime_checks'] == 779 and pure['failures'] == 0
    for path, fingerprint in pure['production_and_evidence_sha256'].items():
        assert sha((ROOT / path).read_bytes()) == fingerprint, path
    tested = load(ROOT / rule['runtime_tested_inputs']['path'])
    main_deltas = {path for path, fingerprint in tested['inputs'].items() if sha((ROOT / path).read_bytes()) != fingerprint}
    assert main_deltas == {'scripts/combat/telegraphed_area_runtime.gd'}
    assert 'Main453' in rule['main_source_boundary'] and '779' in rule['main_source_boundary']
    fixture = load(ROOT / rule['actual_main_fixture']['path'])
    assert int(fixture['version']) == 53
    assert builder.build(data, load(REF / 'art/manifest.json')) == html
    old_tree, new_tree = ast.parse(baseline('tools/build_reference.py').decode()), ast.parse((ROOT / 'tools/build_reference.py').read_text())
    for tree in [old_tree, new_tree]:
        tree.body = [node for node in tree.body if not isinstance(node, ast.FunctionDef) or node.name != 'exploration_map_body']
    assert ast.dump(old_tree) == ast.dump(new_tree), 'Builder edits must stay in the current-map body'
    assets = ['docs/reference/reference.css', 'docs/reference/reference.js', 'docs/reference/art/manifest.json']
    for path in assets: assert (ROOT / path).read_bytes() == baseline(path), path
    evidence = {'baseline_commit': BASE, 'passed': True, 'changed_cards': sorted(changed),
        'preserved_card_count': len(preserved_cards), 'preserved_raw_top_level_count': len(preserved_top),
        'card_count': len(current), 'numeric_fact_count': len(expected), 'unique_ids': len(page.ids),
        'verified_links': len(page.links), 'actual_main_checks': int(report['checks']),
        'scope': 'Static bounded F8 checks only. Reuses actual Main report and lawful fixture; no map, battle, source coverage, art generation or full exporter run.'}
    (QA / 'preservation.json').write_text(json.dumps({'raw_top_level_sha256': preserved_top, 'unchanged_assets': assets,
        'current_ginkgo_changed_fields': ['boss_definition', 'description'], 'historical_ginkgo_archive_unchanged': True,
        'other_three_map_cards_unchanged': True, 'geometry_and_roster_tokens_unchanged': True}, ensure_ascii=False, indent=2) + '\n')
    (QA / 'card-sha256.json').write_text(json.dumps(preserved_cards, ensure_ascii=False, indent=2) + '\n')
    (QA / 'final-result.json').write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(evidence, ensure_ascii=False, indent=2))


if __name__ == '__main__': main()

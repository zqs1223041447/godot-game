#!/usr/bin/env python3
"""v120-only bounded reference checks; v119 data and tests stay historical."""
import argparse
import copy
import hashlib
import importlib.util
import json
import re
import subprocess
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
REF = ROOT / 'docs/reference'
QA = ROOT / 'docs/qa/v120-ruins-boss'
BASE = '8c10337d337ecee0f9d3c8fbcfaf1766ad2103d1'
CARD = 'maps-ruins_garden'


def digest(value):
    return hashlib.sha256(value).hexdigest()


def historical(path):
    return subprocess.check_output(['git', 'show', BASE + ':' + path], cwd=ROOT)


def module(path):
    spec = importlib.util.spec_from_file_location(path.stem, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def cards(text):
    matches = re.findall(r'(<article\b[^>]*\bid="([^"]+)".*?</article>)', text, re.S)
    result = {key: raw for raw, key in matches}
    assert len(result) == len(matches), 'Duplicate card IDs'
    return result


class Inspector(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = []
        self.urls = []
        self.values = {}

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if 'id' in attrs:
            self.ids.append(attrs['id'])
        for key in ['href', 'src']:
            if key in attrs:
                self.urls.append(attrs[key])
        if 'data-ruins-attack-value' in attrs:
            key = attrs['data-ruins-attack-value']
            assert key not in self.values, key
            self.values[key] = float(attrs['data-value'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', action='store_true')
    args = parser.parse_args()
    text = (REF / 'catalog.json').read_text()
    old_text = historical('docs/reference/catalog.json').decode()
    catalog, old_catalog = json.loads(text), json.loads(old_text)
    fragment = json.loads((QA / 'ruins-garden-fragment.json').read_text())
    entry = catalog['exploration_maps']['maps']['ruins_garden']
    old_entry = old_catalog['exploration_maps']['maps']['ruins_garden']
    assert fragment == {'ruins_garden': entry}
    merge = module(ROOT / 'tools/merge_ruins_garden_reference.py')
    assert merge.merge(text, fragment) == text, 'Merge must be byte-idempotent'
    assert merge.merge(old_text, fragment) == text, 'Exactly one existing map member may be replaced'
    start, end = merge.member_span(text, ['exploration_maps', 'maps', 'ruins_garden'])
    old_start, old_end = merge.member_span(old_text, ['exploration_maps', 'maps', 'ruins_garden'])
    assert text[:start] == old_text[:old_start] and text[end:] == old_text[old_end:], 'Unrelated catalog bytes changed'
    assert set(entry) == set(old_entry)
    assert {k: v for k, v in entry.items() if k not in {'boss_definition', 'description'}} == {k: v for k, v in old_entry.items() if k not in {'boss_definition', 'description'}}, 'Map economy, seed, roots, routes, geometry and native evidence must remain exact'
    assert '首领庭园缠印锁定玩家起手位置：先离开内圈，再进入环内或继续远离外环；两段不追踪。' in entry['description']
    boss = entry['boss_definition']
    assert boss == {
        'id': 'ruins_garden_slam', 'map_id': 'ruins_garden', 'name': '庭园缠印',
        'target_rule': 'player_at_start', 'trigger_distance': 420.0,
        'profile': {'radius': 90.0, 'windup_seconds': 1.15, 'recovery_seconds': 1.9, 'damage_multiplier': 0.65},
        'pulse_count': 2, 'pulse_interval': 1.0,
        'second_pulse': {'shape': 'annulus', 'inner_radius': 90.0, 'radius': 210.0, 'windup_seconds': 1.0},
        'profile_id': 'ruins_garden_inner_outer', 'balance_version': 'original-ruins-garden-inner-outer-v1'}
    for path in ['tools/export_ruins_garden_reference.gd', 'tools/merge_ruins_garden_reference.py', 'tests/ruins_garden_reference_test.py']:
        assert (ROOT / path).read_bytes() == historical(path), path
    old_qa_changes = subprocess.check_output(['git', 'diff', '--name-only', BASE, '--', 'docs/qa'], cwd=ROOT, text=True).splitlines()
    assert all(path.startswith('docs/qa/v120-ruins-boss/') for path in old_qa_changes), old_qa_changes
    assert not subprocess.check_output(['git', 'diff', '--name-only', BASE, '--', 'docs/reference/art', 'docs/reference/reference.js', 'docs/reference/reference.css'], cwd=ROOT), 'Reference assets or UI scripts changed'

    html = (REF / 'index.html').read_text()
    old_html = historical('docs/reference/index.html').decode()
    current_cards, old_cards = cards(html), cards(old_html)
    assert current_cards.keys() == old_cards.keys()
    changed_cards = [key for key in current_cards if current_cards[key] != old_cards[key]]
    assert changed_cards == [CARD], changed_cards
    for map_id in ['old_garden', 'broken_ruins', 'sunwell_terrace', 'ginkgo_arcade']:
        assert current_cards['maps-' + map_id] == old_cards['maps-' + map_id], map_id
    card = current_cards[CARD]
    for phrase in ['庭园缠印', '两段均锁定玩家起手位置', '不重新锁点', '第一段后额外完整预警', '空心环命中', '身体接触边界仍命中', '起手冻结', '第二段结束后', '原生障碍', '冻结暂停', '起手期间不叠加贴身接触攻击', boss['profile_id'], boss['balance_version']]:
        assert phrase in card, phrase
    for obsolete in ['庭园震地', '130 / 140', '第一响结束后立即返回原圈仍可能被后续回响命中']:
        assert obsolete not in card, obsolete
    inspector = Inspector()
    inspector.feed(html)
    expected_values = {'trigger-distance': 420, 'first-windup': 1.15, 'first-radius': 90, 'second-windup': 1,
                       'inner-radius': 90, 'outer-radius': 210, 'pulse-count': 2, 'pulse-interval': 1,
                       'stage-multiplier': 0.65, 'combined-multiplier': 1.3, 'base-recovery': 1.9}
    assert inspector.values == expected_values
    layout_pattern = r'<svg data-exploration-layout="ruins_garden".*?</svg>'
    assert re.search(layout_pattern, card, re.S).group() == re.search(layout_pattern, old_cards[CARD], re.S).group(), 'Native layout diagram changed'
    svg = ET.fromstring(re.search(r'<svg data-ruins-attack-diagram="inner-outer".*?</svg>', card, re.S).group())
    stages = {g.attrib['data-ruins-attack-stage']: g for g in svg.findall('g')}
    assert set(stages) == {'1', '2'}
    assert stages['1'].attrib['transform'] == 'translate(0 0)'
    assert stages['2'].attrib['transform'] == 'translate(550 0)', 'Both panels must have the same unscaled coordinate units'
    circle = stages['1'].find('circle')
    assert circle.attrib['cx'] == circle.attrib['cy'] == '0'
    assert float(circle.attrib['r']) == boss['profile']['radius']
    annulus = next(p for p in stages['2'].findall('path') if p.attrib.get('data-ruins-attack-shape') == 'annulus')
    assert float(annulus.attrib['data-inner-radius']) == boss['second_pulse']['inner_radius']
    assert float(annulus.attrib['data-outer-radius']) == boss['second_pulse']['radius']
    assert annulus.attrib['fill-rule'] == 'evenodd', 'Second stage must leave a transparent safe inner hole'
    assert annulus.attrib['d'] == 'M-210 0a210 210 0 1 0 420 0a210 210 0 1 0 -420 0Z M-90 0a90 90 0 1 0 180 0a90 90 0 1 0 -180 0Z'
    for stage in stages.values():
        center = next(p for p in stage.findall('path') if 'data-ruins-attack-center' in p.attrib)
        assert center.attrib['data-ruins-attack-center'] == 'frozen-player-start'
        assert center.attrib['d'] == 'M-7 0H7M0 -7V7'
    payload = json.loads(re.search(r'<script id="reference-data" type="application/json">(.*?)</script>', html, re.S).group(1))
    record = next(x for x in payload['records'] if x['id'] == CARD)
    assert all(term in record['search'] for term in ['遗迹庭园', 'ruins_garden', '庭园缠印', '玩家起手位置', '空心环'])
    assert len(inspector.ids) == len(set(inspector.ids))
    ids = set(inspector.ids)
    for url in inspector.urls:
        parsed = urlsplit(url)
        if parsed.scheme or parsed.netloc:
            continue
        if not parsed.path:
            assert not parsed.fragment or unquote(parsed.fragment) in ids, url
        else:
            assert (REF / unquote(parsed.path)).is_file(), url
    builder = module(ROOT / 'tools/build_reference.py')
    art = json.loads((REF / 'art/manifest.json').read_text())
    assert builder.build(catalog, art) == html
    assert builder.build(old_catalog, art) == old_html, 'v119 inputs must reproduce full v119 HTML bytes'
    # Also preserve the v118 generator path with the native map absent.
    v118_catalog = json.loads(historical('docs/reference/catalog.json'))
    del v118_catalog['exploration_maps']['maps']['ruins_garden']
    v119_baseline = json.loads((ROOT / 'docs/qa/v119-reference/baseline.json').read_text())
    assert digest(builder.build(v118_catalog, art).encode()) == v119_baseline['html_sha256']
    # Actual diagram/value text must follow the supplied definition, rather than
    # accidentally retaining hardcoded production radii or timing in labels.
    probe = copy.deepcopy(boss)
    probe['profile']['radius'] = 92.0
    probe['second_pulse']['inner_radius'] = 92.0
    probe['second_pulse']['radius'] = 212.0
    probe['profile']['windup_seconds'] = 1.17
    probe_html = builder.ruins_garden_attack_body(probe, lambda pairs: json.dumps(pairs, ensure_ascii=False))
    assert 'r="92"' in probe_html and 'data-outer-radius="212"' in probe_html
    assert '第一段半径92实心圆，第二段内半径92外半径212空心环' in probe_html
    assert '完整预警 1.17 秒' in probe_html
    report = {'baseline_commit': BASE, 'changed_cards': changed_cards, 'preserved_card_count': len(current_cards) - 1,
              'old_four_map_cards_byte_identical': True, 'catalog_single_member_replacement': True,
              'ruins_fields_other_than_boss_definition_and_description_identical': True, 'v119_and_v118_generator_compatibility': True,
              'native_layout_diagram_identical': True, 'same_scale_circle_annulus_diagram': True,
              'display_values': inspector.values, 'unique_html_ids': len(ids), 'all_local_links_exist': True,
              'historical_qa_exporter_merge_and_v119_test_unchanged': True,
              'sha256': {path: digest((ROOT / path).read_bytes()) for path in ['tools/build_reference.py', 'tests/ruins_garden_attack_reference_test.py', 'docs/reference/catalog.json', 'docs/reference/index.html', 'docs/qa/v120-ruins-boss/ruins-garden-fragment.json']}}
    if args.report:
        (QA / 'reference-static-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(f'RUINS_ATTACK_REFERENCE passed: exact two-stage values, same-scale hollow annulus, frozen-player lock, all local links; only one catalog member and one card changed; {len(current_cards) - 1} cards preserved; v118/v119 full-build compatibility; historical QA unchanged')


if __name__ == '__main__':
    main()

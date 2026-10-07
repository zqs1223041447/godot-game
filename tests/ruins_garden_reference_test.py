#!/usr/bin/env python3
"""Focused offline native-card checks; no historical exporter or game execution."""
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
QA = ROOT / 'docs/qa/v119-reference'
NEW_ID = 'maps-ruins_garden'
CHANGED = {'town_services-map_device', 'rules-exploration_maps'}


def digest(value):
    return hashlib.sha256(value).hexdigest()


def object_hash(value):
    return digest(json.dumps(value, sort_keys=True, separators=(',', ':')).encode())


def module(path):
    spec = importlib.util.spec_from_file_location(path.stem, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


class Inspector(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = []
        self.urls = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if 'id' in attrs:
            self.ids.append(attrs['id'])
        for key in ['href', 'src']:
            if key in attrs:
                self.urls.append(attrs[key])


def main():
    baseline = json.loads((QA / 'baseline.json').read_text())
    text = (REF / 'catalog.json').read_text()
    catalog = json.loads(text)
    fragment = json.loads((QA / 'ruins-garden-fragment.json').read_text())
    entry = catalog['exploration_maps']['maps']['ruins_garden']
    assert fragment == {'ruins_garden': entry}
    merge_tool = module(ROOT / 'tools/merge_ruins_garden_reference.py')
    assert merge_tool.merge(text, fragment) == text, 'Merge must be byte-idempotent'
    start, end = merge_tool.member_span(text, ['exploration_maps', 'maps', 'ruins_garden'])
    prefix = text.rfind(',\n\t\t\t"ruins_garden": ', 0, start)
    assert prefix >= 0
    restored = text[:prefix] + text[end:]
    assert digest(restored.encode()) == baseline['catalog_sha256'], 'All historical catalog bytes must survive removal of the one additive field'
    assert entry['native_entry'] and entry['test_available'] is False and 'test_profile' not in entry
    assert len(catalog['exploration_maps']['maps']) == 5
    tiers = entry['tiers']
    assert [x['profile']['wave'] for x in tiers] == [1, 4, 8]
    assert [x['profile']['fee'] for x in tiers] == [0, 4, 8]
    assert [x['profile']['completion_reward'] for x in tiers] == [4, 8, 12]
    assert [x['maximum_modifier_bonus'] for x in tiers] == [2, 4, 4]
    assert [set(x['eligible_special_ids']) for x in tiers] == [set(), {'elemental_aegis', 'frost_patrol'}, {'elemental_aegis', 'frost_patrol', 'storm_patrol', 'chaos_patrol'}]
    geometry = entry['geometry']
    marks = geometry['landmarks']
    native = entry['native_reference']
    assert geometry['id'] == geometry['source_map_id'] == 'ruins_garden'
    assert geometry['walls'] == [] and len(geometry['module_polygons']) == 4
    assert sum(map(len, geometry['module_polygons'])) == native['vertex_count'] == 99
    assert len(geometry['module_instances']) == 3
    assert geometry['bounds']['size'] == [3600, 2400]
    assert [x['root_count'] for x in marks['outposts']] == [3, 5, 3, 5, 3, 5]
    routes = marks['route_segments']
    assert len(routes) == native['prepared_route_count'] == 14
    cursor = 0
    split_indices = []
    for index, original in enumerate(native['source_route_segments']):
        chain = []
        current = original['from']
        while cursor < len(routes):
            route = routes[cursor]
            assert route['from'] == current and route['width'] == original['width'] == 72
            chain.append(route)
            current = route['to']
            cursor += 1
            if current == original['to']:
                break
        assert current == original['to']
        if len(chain) > 1:
            assert len(chain) == 2
            split_indices.append(index)
        else:
            assert chain[0] == original
    assert split_indices == [0, 10] and cursor == 14
    plan = entry['plan_example']
    assert len(plan['spawn_records']) == len(plan['roots']) == plan['total'] == 25
    assert plan['mechanism_config'] == {} and plan['optional_encounters'] == []
    assert len({x['spawn_key'] for x in plan['spawn_records']}) == 25
    for record, root in zip(plan['spawn_records'], plan['roots']):
        for key in ['position', 'spawn_key', 'actor_id', 'root_id', 'template_id', 'outpost_id']:
            assert record[key] == root[key]
        assert root['generation'] == 0 and root['awake'] is False
        assert record['reward_route'] == 'standard' and record['encounter_id'] == ''
    boss = entry['boss_definition']
    assert boss['id'] == 'ruins_garden_slam' and boss['target_rule'] == 'self_at_start'
    assert boss['trigger_distance'] == 140
    assert boss['profile'] == {'radius': 130.0, 'windup_seconds': 0.9, 'recovery_seconds': 1.7, 'damage_multiplier': 1.4}

    html = (REF / 'index.html').read_text()
    card_pairs = re.findall(r'(<article\b[^>]*\bid="([^"]+)".*?</article>)', html, re.S)
    cards = {key: raw for raw, key in card_pairs}
    assert len(cards) == len(card_pairs) == baseline['old_card_count'] + 1
    preserved = {key: digest(raw.encode()) for key, raw in cards.items() if key not in CHANGED | {NEW_ID}}
    assert object_hash(preserved) == baseline['preserved_cards_sha256'], 'Unrelated historical cards changed'
    for key, expected in baseline['old_map_cards'].items():
        assert digest(cards[key].encode()) == expected, key
    new = cards[NEW_ID]
    for phrase in ['准备地图 → 开启地图', '不属于历史免费测试地图入口', '25 个真实实体', '两处绕行', '庭园震地', '0.9 秒', '130 / 140', '1.7 秒', '1.4 ×']:
        assert phrase in new, phrase
    assert '存档仍为schema' not in new and '独立测试地图免费，固定地图等级' not in new
    for tier in tiers:
        profile = tier['profile']
        row = '<th scope="row">' + profile['name'] + '</th>' + ''.join('<td>' + str(value) + '</td>' for value in [profile['wave'], profile['fee'], profile['completion_reward'], tier['maximum_modifier_bonus']])
        assert row in new, 'Displayed tier economics must match compiler output'
    for map_id in catalog['exploration_maps']['maps']:
        assert f'href="#maps-{map_id}"' in cards['town_services-map_device']
    svg = ET.fromstring(re.search(r'<svg data-exploration-layout="ruins_garden".*?</svg>', new, re.S).group())
    polygons = svg.findall('polygon')
    assert len(polygons) == 4
    for index, (polygon, expected) in enumerate(zip(polygons, geometry['module_polygons'])):
        assert polygon.attrib['data-exploration-contour'] == str(index)
        assert [[float(v) for v in pair.split(',')] for pair in polygon.attrib['points'].split()] == expected
    assert not [x for x in svg if 'data-exploration-wall' in x.attrib], 'Native card must never render bounding boxes'
    lines = svg.findall('line')
    assert len(lines) == 14
    for index, (line, route) in enumerate(zip(lines, routes)):
        assert line.attrib['data-exploration-route'] == str(index)
        assert [float(line.attrib[x]) for x in ['x1', 'y1']] == route['from']
        assert [float(line.attrib[x]) for x in ['x2', 'y2']] == route['to']
        assert float(line.attrib['stroke-width']) == route['width']
    spawns = [x for x in svg if 'data-exploration-spawn' in x.attrib]
    assert len(spawns) == 25
    for dot, record in zip(spawns, plan['spawn_records']):
        assert dot.attrib['data-exploration-spawn'] == record['spawn_key']
        assert dot.attrib['data-template'] == record['template_id']
        assert [float(dot.attrib[x]) for x in ['cx', 'cy']] == record['position']
    signs = [x for x in svg if 'data-exploration-sign' in x.attrib]
    assert len(signs) == 7
    for sign, landmark in zip(signs, marks['outposts'] + [marks['boss']]):
        assert sign.attrib['data-exploration-sign'] == (landmark['id'] if landmark in marks['outposts'] else 'boss')
        x, y = landmark['sign_position']
        assert sign.attrib['d'] == f'M{x} {y-20}v40M{x-20} {y-20}h40v22h-40z'
    entrance = next(x for x in svg if 'data-exploration-entry' in x.attrib)
    assert [float(entrance.attrib[x]) for x in ['cx', 'cy']] == marks['entry'] == geometry['spawn']
    ox, oy = geometry['bounds']['position']
    width, height = geometry['bounds']['size']
    points = [p for polygon in geometry['module_polygons'] for p in polygon]
    points += [r['position'] for r in plan['spawn_records']] + [marks['entry']]
    points += [r[k] for r in routes for k in ['from', 'to']]
    assert all(ox <= x <= ox+width and oy <= y <= oy+height for x, y in points)
    embedded = json.loads(re.search(r'<script id="reference-data" type="application/json">(.*?)</script>', html, re.S).group(1))
    record = next(x for x in embedded['records'] if x['id'] == NEW_ID)
    assert record['cat'] == 'maps' and record['status'] == 'implemented'
    assert all(term in record['search'] for term in ['遗迹庭园', 'ruins_garden', '原生', '准备地图'])
    inspector = Inspector()
    inspector.feed(html)
    assert len(inspector.ids) == len(set(inspector.ids)), 'Duplicate HTML IDs'
    ids = set(inspector.ids)
    for url in inspector.urls:
        parsed = urlsplit(url)
        if parsed.scheme or parsed.netloc:
            continue
        if not parsed.path:
            assert not parsed.fragment or unquote(parsed.fragment) in ids, url
        else:
            assert (REF / unquote(parsed.path)).is_file(), url
    for paths, expected in baseline['unchanged_groups'].items():
        names = subprocess.check_output(['git', 'ls-files', '--', *paths.split(';')], cwd=ROOT, text=True).splitlines()
        names = [name for name in names if not name.startswith('docs/qa/v119-reference/')]
        actual = {name: digest((ROOT / name).read_bytes()) for name in names}
        assert len(actual) == expected['count'] and object_hash(actual) == expected['sha256'], paths
    builder = module(ROOT / 'tools/build_reference.py')
    art = json.loads((REF / 'art/manifest.json').read_text())
    assert builder.build(catalog, art) == html, 'Deterministic full HTML build'
    # Compatibility: without the additive field the new generator reproduces all
    # original cards, including the original map-device and rule entry.
    assert digest(builder.build(json.loads(restored), art).encode()) == baseline['html_sha256'], 'Legacy catalogs must reproduce complete original HTML bytes'
    legacy_cards = {key: raw for raw, key in re.findall(r'(<article\b[^>]*\bid="([^"]+)".*?</article>)', builder.build(json.loads(restored), art), re.S)}
    assert len(legacy_cards) == baseline['old_card_count']
    assert object_hash({key: digest(raw.encode()) for key, raw in legacy_cards.items() if key not in CHANGED}) == baseline['preserved_cards_sha256']
    print(f'RUINS_REFERENCE_STATIC passed: 4 exact polygons/99 vertices, 14 routes, 25 roots, 7 signs, 5 map links; {len(cards)} cards and {len(ids)} unique IDs; all local links, historical catalog bytes, old cards, production/art/4973 historical QA files preserved')


if __name__ == '__main__':
    main()

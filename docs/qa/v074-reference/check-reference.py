#!/usr/bin/env python3
"""Focused v74 source-entry/monster-speed reference and exact v73 preservation."""
from copy import deepcopy
import hashlib
from html.parser import HTMLParser
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
QA = Path(__file__).resolve().parent
REF = ROOT / 'docs/reference'


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def digest(value):
    return sha(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode())


def near(left, right):
    assert math.isfinite(left) and abs(left - right) <= max(1e-9, abs(right) * 1e-10), (left, right)


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids, self.links, self.assets = [], [], []
        self.values, self.labels = {}, {}
        self.active = None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if 'id' in attrs:
            self.ids.append(attrs['id'])
        if 'href' in attrs:
            self.links.append(attrs['href'])
        if 'src' in attrs:
            self.assets.append(attrs['src'])
        if 'data-source-monster-value' in attrs:
            key = attrs['data-source-monster-value']
            assert key not in self.values, key
            self.values[key] = float(attrs['data-value'])
            self.labels[key] = ''
            self.active = key

    def handle_data(self, text):
        if self.active:
            self.labels[self.active] += text

    def handle_endtag(self, tag):
        if tag == 'strong':
            self.active = None


def main():
    baseline = json.loads((QA / 'v073-baseline.json').read_text())
    data = json.loads((REF / 'catalog.json').read_text())
    rule = data['source_monster_movement']
    assert data['game_version'] == '0.74.0'
    assert data['save_version'] == rule['save_version'] == 47
    assert rule['equipment_vocabulary'] == 46 and rule['source_policy'] == 45
    assert set(data) == set(baseline['top_level_sha256']) | {'source_monster_movement'}
    preserved_sections = []
    for key, expected in baseline['top_level_sha256'].items():
        if key in ['game_version', 'mechanisms']:
            continue
        assert digest(data[key]) == expected, 'Historical catalog section changed: ' + key
        preserved_sections.append(key)
    assert len(baseline['mechanisms']) == rule['legacy_definition_count'] == 23
    assert len(data['mechanisms']) == rule['current_definition_count'] == 24
    assert set(data['mechanisms']) - set(baseline['mechanisms']) == {'source_gale_stride'}
    for key, definition in baseline['mechanisms'].items():
        assert data['mechanisms'][key] == definition, key
    assert rule['mechanism_id'] == 'source_gale_stride' and rule['legacy_id'] == 'gale_stride'
    entry = rule['source_entry']
    assert entry['node_id'] == '63417' and entry['stat_index'] == 1
    assert entry['raw_line'] == '4% increased Movement Speed'
    tree = data['source_tree']
    assert tree['nodes']['63417']['stats'][1] == entry['raw_line']
    assert entry['source_hash'] == tree['source_sha256']
    assert entry['source_version'] == tree['source_version']
    assert entry['source_commit'] == tree['source_commit']
    assert entry['source_url'] == 'https://raw.githubusercontent.com/grindinggear/skilltree-export/' + tree['source_commit'] + '/data.json'
    definition = rule['definition']
    assert definition['source_entry'] == entry and definition['source_refs'] == [entry]
    assert definition['source_line'] == entry['raw_line']
    assert definition['source_policy'] == definition['source_save_version'] == 45
    effect = rule['source_effect']
    assert effect['supported'] and effect['grants'] == [{'stat': 'move_speed_increased', 'mode': 'increased', 'value': .04}]
    assert definition['stats'] == {'move_speed_increased': .04}
    for actor in ['player', 'monster']:
        resolved = rule[actor + '_grant']
        assert resolved['ok'] and resolved['errors'] == []
        assert resolved['actor'] == actor and resolved['role_coefficient'] == 1.0
        assert resolved['stats'] == definition['stats'] and resolved['mechanism_ids'] == ['source_gale_stride']
        assert resolved['source_grants'] == [definition]
    new = data['mechanisms']['source_gale_stride']
    for key, value in definition.items():
        assert new[key] == value, key
    assert new['supported_actors'] == ['player', 'monster'] and new['support_reason'] == ''
    assert rule['legacy_grant']['stats'] == baseline['mechanisms']['gale_stride']['stats'] == {'move_speed': 3.12}
    assert rule['actor_coefficient'] == 1.0
    assert rule['legacy_pool'] == ['ember_power', 'gale_stride', 'grove_vitality', 'aegis_capacity', 'aegis_recovery']
    expected_pool = rule['legacy_pool'].copy()
    expected_pool[1] = 'source_gale_stride'
    assert rule['current_pool'] == expected_pool
    assert rule['formula'] == '(species + wave + other_flat) * (1 + move_speed_increased)'
    expected_order = [(wave, template) for wave in [1, 6, 10, 15] for template in ['crawler', 'skitter', 'brute']]
    assert [(row['wave'], row['template_id']) for row in rule['budget']] == expected_order
    rendered = {'increase': (.04, True), 'coefficient': (1., False), 'legacy-flat': (3.12, False),
                'legacy-count': (23, False), 'current-count': (24, False), 'save-version': (47, False),
                'vocabulary': (46, False), 'source-policy': (45, False)}
    for row in rule['budget']:
        base, legacy, current = [row[key] for key in ['base', 'legacy', 'current']]
        for enemy in [base, legacy, current]:
            assert enemy['template_id'] == row['template_id'] and enemy['wave'] == row['wave']
            assert enemy['rarity'] == 'magic' and enemy['reward_eligible']
        assert base['mechanism_ids'] == [] and base['mechanism_stats'] == {}
        assert legacy['mechanism_ids'] == ['gale_stride'] and legacy['mechanism_stats'] == {'move_speed': 3.12}
        assert current['mechanism_ids'] == ['source_gale_stride'] and current['mechanism_stats'] == {'move_speed_increased': .04}
        assert 'mechanism_source_grants' not in base and 'mechanism_source_grants' not in legacy
        assert current['mechanism_source_grants'] == [definition]
        near(legacy['speed'], base['speed'] + rule['legacy_grant']['stats']['move_speed'])
        near(current['speed'], base['speed'] * (1 + rule['monster_grant']['stats']['move_speed_increased']))
        near(row['speed_delta'], current['speed'] - legacy['speed'])
        near(row['relative_to_legacy'], current['speed'] / legacy['speed'] - 1)
        unchanged = []
        for enemy in [base, legacy, current]:
            cleaned = deepcopy(enemy)
            for key in ['speed', 'mechanism_ids', 'mechanism_stats', 'mechanism_policy', 'mechanism_source_grants']:
                cleaned.pop(key, None)
            unchanged.append(cleaned)
        assert unchanged[0] == unchanged[1] == unchanged[2]
        prefix = str(row['wave']) + '-' + row['template_id']
        for key in ['base', 'legacy', 'current']:
            rendered[prefix + '-' + key] = (row[key]['speed'], False)
        rendered[prefix + '-delta'] = (row['speed_delta'], False)
        rendered[prefix + '-relative'] = (row['relative_to_legacy'], True)
    for path, expected in baseline['preserved_files'].items():
        assert sha((ROOT / path).read_bytes()) == expected, path
    baseline_pngs = {path for path in baseline['preserved_files'] if path.endswith('.png')}
    actual_pngs = {path.relative_to(ROOT).as_posix() for folder in [ROOT / 'assets', ROOT / 'data', REF] for path in folder.rglob('*.png')}
    assert actual_pngs == baseline_pngs
    page = Page()
    html = (REF / 'index.html').read_text()
    page.feed(html)
    assert len(page.ids) == len(set(page.ids))
    assert set(baseline['old_html_anchors']) <= set(page.ids)
    assert set(page.ids) - set(baseline['old_html_anchors']) == {'mechanisms-source_gale_stride', 'rules-source_monster_movement'}
    assert page.values.keys() == rendered.keys()
    for key, (amount, is_percent) in rendered.items():
        near(page.values[key], amount)
        assert page.labels[key].strip() == format(amount * (100 if is_percent else 1), 'g') + ('%' if is_percent else ''), key
    for link in page.links:
        if link.startswith('#'):
            assert link[1:] in page.ids, link
        elif link and not link.startswith(('http:', 'https:', 'mailto:')):
            assert (REF / link.split('#')[0]).is_file(), link
    for asset in page.assets:
        assert not asset.startswith(('http:', 'https:')) and (REF / asset).is_file(), asset
    for text in ['历史机制定义（保留）', '当前单条源绑定', '旧固定投影', '不表示所有源基石均已共享', 'stat_index 1', '每帧不重新解析源树', '池数量、次序', '当前源词条']:
        assert text in html, text
    report = {'passed': True, 'baseline_commit': baseline['baseline_commit'],
              'historical_catalog_sections_preserved': preserved_sections, 'legacy_definitions_preserved': 23,
              'new_current_source_bindings': 1, 'budget_rows_from_catalog': len(rule['budget']),
              'authoritative_html_values_and_labels_checked': len(rendered),
              'save_version': 47, 'equipment_vocabulary': 46, 'source_policy': 45,
              'preserved_file_count': len(baseline['preserved_files']), 'old_pngs_preserved': len(baseline_pngs), 'new_art_files': 0,
              'source_coverage_byte_identical': True, 'old_html_anchors_preserved': len(baseline['old_html_anchors']),
              'new_html_anchors': sorted(set(page.ids) - set(baseline['old_html_anchors'])),
              'all_anchor_and_local_file_links_valid': True,
              'catalog_sha256': sha((REF / 'catalog.json').read_bytes()), 'html_sha256': sha((REF / 'index.html').read_bytes()),
              'scope': 'One full Godot export plus one new-chapter-only correction; recover historical JSON number types from the hash-verified baseline; rebuild HTML for corrected schema and effective shared-card wording; focused source-binding and preservation checks; no historical full test rerun, import, UI, art or package work'}
    with (QA / 'v073-preservation.json').open('x') as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2)
        stream.write('\n')
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()

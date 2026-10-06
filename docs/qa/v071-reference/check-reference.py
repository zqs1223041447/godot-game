#!/usr/bin/env python3
"""Validate the bounded v71 F8 addition against actual outputs and v70 bytes."""
from copy import deepcopy
import hashlib
from html.parser import HTMLParser
import json
import math
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
QA = Path(__file__).resolve().parent
REF = ROOT / 'docs/reference'
BASE = '4166822ff7a487bb498c7086b20e2823e4e71edb'


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def oldbytes(path):
    return subprocess.check_output(['git', 'show', BASE + ':' + path], cwd=ROOT)


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
        if 'data-mist-value' in attrs:
            key = attrs['data-mist-value']
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
    old = json.loads(oldbytes('docs/reference/catalog.json'))
    data = json.loads((REF / 'catalog.json').read_text())
    monster = data['monsters']['mist_skitter']
    budget, actual = monster['encounter_budget'], monster['runtime_example']
    assert data['game_version'] == '0.71.0' and data['save_version'] == old['save_version'] == 45
    assert monster['name'] == '雾羽掠行体' and monster['kind'] == 1 and monster['rarity'] == 'normal'
    assert monster['mechanisms'] == monster['death_spawns'] == []
    assert monster['example_wave'] == actual['wave'] == 6
    assert monster['source_ratings'] == {'accuracy': 100, 'armour': 0, 'evasion': 1600}
    assert monster['telegraph_policy'] == {} and actual['evasion'] == 1600
    assert budget['policy'] == {'evasion': 1600, 'health_multiplier': .8, 'damage_multiplier': .85}
    baseline = budget['baseline_example']
    assert baseline['template_id'] == 'skitter' and baseline['wave'] == actual['wave'] and baseline['rarity'] == 'normal'
    for field in ['health', 'max_health']:
        near(actual[field], baseline[field] * .8)
    near(actual['damage'], baseline['damage'] * .85)
    assert actual['health'] == 36 and baseline['health'] == 45
    near(actual['damage'], 9.775)
    for field in ['kind', 'rarity', 'speed', 'radius', 'attack_speed', 'attack_timer', 'contact_weights', 'xp_reward', 'reward_eligible', 'root_id', 'generation', 'death_spawns', 'mechanism_ids']:
        assert actual[field] == baseline[field], field
    assert budget['formal_profiles'] == [{'tier': 1, 'wave': 3, 'eligible': False}, {'tier': 2, 'wave': 6, 'eligible': True}, {'tier': 3, 'wave': 10, 'eligible': True}]
    assert budget['fixed_test_wave'] == 6 and budget['fixed_test_eligible'] is False
    assert budget['maximum_per_camp'] == 1 and budget['maximum_per_map'] == 3 and budget['map_root_count'] == 36
    assert budget['baseline_evasion'] == 320 and budget['roster_example_seed'] == 43
    roster = json.loads((ROOT / 'docs/qa/v071-mist-skitter/roster/roster_report.json').read_text())
    assert roster['failures'] == 0 and roster['cases'] == 1184
    for row in budget['roster_examples']:
        assert row['tier'] in [2, 3] and row['wave'] == {2: 6, 3: 10}[row['tier']]
        admissions = row['mist_admission_indices']
        assert set(admissions) == {'camp_west', 'camp_north', 'camp_east'}
        if row['special_ids']:
            assert row['special_ids'] == ['storm_patrol'] and all(value == [] for value in admissions.values())
        else:
            expected = next(example for example in roster['examples'] if example['tier'] == row['tier'] and example['seed'] == 43)
            assert [index for camp in ['camp_west', 'camp_north', 'camp_east'] for index in admissions[camp]] == expected['mist_admission_indices'] == [6, 21, 25]
    assert len(budget['roster_examples']) == 4
    rendered = {'evasion': 1600, 'health-multiplier': .8, 'damage-multiplier': .85, 'maximum-per-camp': 1,
                'maximum-per-map': 3, 'map-root-count': 36, 'fixed-test-wave': 6, 'baseline-evasion': 320, 'resolute-chance': 1}
    ratios = {'health-multiplier', 'damage-multiplier', 'resolute-chance'}
    assert len(budget['accuracy_probes']) == 5
    for row, accuracy, old_chance, chance in zip(budget['accuracy_probes'], [100, 284, 304, 414, 600], [.88, 1, 1, 1, 1], [.45, .77, .79, .87, .96]):
        assert row == {'accuracy': accuracy, 'baseline_chance': old_chance, 'mist_chance': chance, 'resolute_chance': 1}
        key = str(accuracy)
        rendered.update({'accuracy-' + key: accuracy, 'baseline-chance-' + key: old_chance, 'mist-chance-' + key: chance})
        ratios.update({'baseline-chance-' + key, 'mist-chance-' + key})
    # Explicitly allow exactly one new template subtree and version metadata.
    projected = deepcopy(old)
    projected['game_version'] = '0.71.0'
    projected['monsters']['mist_skitter'] = monster
    assert projected == data, 'Catalog changed outside game_version and monsters.mist_skitter'
    assert (REF / 'source-tree-coverage.json').read_bytes() == oldbytes('docs/reference/source-tree-coverage.json')
    page, oldpage = Page(), Page()
    html = (REF / 'index.html').read_text()
    page.feed(html)
    oldpage.feed(oldbytes('docs/reference/index.html').decode())
    assert page.values.keys() == rendered.keys()
    for key, amount in rendered.items():
        near(page.values[key], amount)
        label = f'{amount * 100:.0f}%' if key in ratios else f'{amount:g}'
        assert page.labels[key].strip() == label, (key, page.labels[key], label)
    assert len(page.ids) == len(set(page.ids))
    assert set(page.ids) - set(oldpage.ids) == {'monsters-mist_skitter'}
    assert set(oldpage.ids) <= set(page.ids)
    for link in page.links:
        if link.startswith('#'):
            assert link[1:] in page.ids, link
        elif link and not link.startswith(('http:', 'https:', 'mailto:')):
            assert (REF / link.split('#')[0]).is_file(), link
    for asset in page.assets:
        assert not asset.startswith(('http:', 'https:')) and (REF / asset).is_file(), asset
    for wording in ['高闪避·较脆', '没有合格名额则为0', '雷纹巡逻优先', '不替换蓝金怪、首领或死亡后代', '并非构筑排行或伤害增幅', '旧固定波次', '不会绕过闪避']:
        assert wording in html, wording
    paths = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', BASE, 'assets', 'data', 'docs/reference'], cwd=ROOT, text=True).splitlines()
    preserved = [path for path in paths if path.endswith('.png') or path.startswith('data/')]
    preserved += ['docs/reference/reference.css', 'docs/reference/reference.js', 'docs/reference/art/manifest.json', 'docs/reference/source-tree-coverage.json']
    hashes = {path: sha((ROOT / path).read_bytes()) for path in preserved}
    for path, digest in hashes.items():
        assert digest == sha(oldbytes(path)), path
    old_pngs = sorted(path for path in paths if path.endswith('.png'))
    assert old_pngs == sorted(path.relative_to(ROOT).as_posix() for folder in [ROOT / 'assets', REF] for path in folder.rglob('*.png'))
    result = {'passed': True, 'baseline_commit': BASE,
              'exact_catalog_allowed_changes': ['game_version', 'monsters.mist_skitter'],
              'old_catalog_values_preserved': True, 'source_coverage_byte_identical': True,
              'save_schema_preserved': 45, 'authoritative_html_values_and_labels_checked': len(rendered),
              'old_html_anchors_preserved': len(oldpage.ids), 'html_unique_ids': len(page.ids),
              'only_new_anchor': 'monsters-mist_skitter', 'all_anchor_and_local_file_links_valid': True,
              'same_rule_accuracy_probes': budget['accuracy_probes'], 'actual_roster_examples_match_passed_gate': True,
              'old_asset_pngs_preserved': len([path for path in old_pngs if path.startswith('assets/')]),
              'old_reference_pngs_preserved': len([path for path in old_pngs if path.startswith('docs/reference/')]),
              'catalog_bytes': (REF / 'catalog.json').stat().st_size,
              'catalog_sha256': sha((REF / 'catalog.json').read_bytes()),
              'html_sha256': sha((REF / 'index.html').read_bytes()), 'unchanged_files': hashes}
    with (QA / 'v070-preservation.json').open('x') as stream:
        json.dump(result, stream, ensure_ascii=False, indent=2)
        stream.write('\n')
    print(json.dumps({key: value for key, value in result.items() if key != 'unchanged_files'}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()

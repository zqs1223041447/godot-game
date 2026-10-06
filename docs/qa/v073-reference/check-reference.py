#!/usr/bin/env python3
"""Bounded v73 actual-Main projection, thaw timing, and exact v72 preservation."""
from copy import deepcopy
import hashlib
from html.parser import HTMLParser
import json
import math
from pathlib import Path
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[3]
QA = Path(__file__).resolve().parent
REF = ROOT / 'docs/reference'
BASE = '70b75bc'
ICON_HASH = 'dad5f51c2f10b2ca932ba0fe5a4f3ed608e94eea41c30e6392af964b4450e673'


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def oldbytes(path):
    return subprocess.check_output(['git', 'show', BASE + ':' + path], cwd=ROOT)


def near(left, right):
    assert math.isfinite(left) and abs(left - right) <= max(1e-9, abs(right) * 1e-10), (left, right)


def differences(left, right, path=()):
    if isinstance(left, dict) and isinstance(right, dict):
        for key in sorted(left.keys() | right.keys()):
            if key not in left:
                yield 'added', path + (key,), None, right[key]
            elif key not in right:
                yield 'removed', path + (key,), left[key], None
            else:
                yield from differences(left[key], right[key], path + (key,))
    elif isinstance(left, list) and isinstance(right, list) and len(left) == len(right):
        for i, (a, b) in enumerate(zip(left, right)):
            yield from differences(a, b, path + (i,))
    elif left != right:
        yield 'changed', path, left, right


def replace(projected, path, before, after):
    obj = projected
    for key in path[:-1]:
        obj = obj[key]
    assert obj[path[-1]] == before, path
    obj[path[-1]] = deepcopy(after)


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
        if 'data-frost-lock-value' in attrs:
            key = attrs['data-frost-lock-value']
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
    rule = data['frost_lock']
    assert data['game_version'] == '0.73.0' and data['save_version'] == rule['minimum_save_version'] == 47
    assert rule['equipment_vocabulary'] == 46 and rule['source_policy'] == 45
    assert rule['support_id'] == 'frost_lock' and rule['skills'] == ['frost'] and rule['mutually_exclusive_with'] == ['lingering_chill']
    policy = {'duration_by_rarity': {'normal': .60, 'magic': .60, 'rare': .35, 'boss': .20}, 'immunity_seconds': 1.50, 'hit_multiplier': .75, 'mana_multiplier': 1.20}
    assert rule['policy'] == policy and rule['max_targets'] == 100
    assert rule['normal_reward_definition_count'] == 26 and rule['normal_reward_pool_includes_support'] is False
    assert rule['whole_build_valid'] and rule['matches_actual_main'] and rule['save_attempts'] == 0
    acceptance = json.loads((ROOT / 'docs/qa/v073-gameplay/acceptance-summary.json').read_text())
    assert acceptance['passed'] and acceptance['checks'] == 328 and acceptance['failures'] == 0
    for field, hashfield, filename in [('fixture', 'fixture_sha256', 'selected.json'), ('expected_fixture', 'expected_sha256', 'selected-casts.json')]:
        assert rule[field] == 'docs/qa/v073-gameplay/fixtures/' + filename
        assert sha((ROOT / rule[field]).read_bytes()) == rule[hashfield] == acceptance['fixtures']['fixtures/' + filename]
    raw = json.loads((ROOT / rule['fixture']).read_text())
    expected = json.loads((ROOT / rule['expected_fixture']).read_text())
    assert raw['version'] == 47 and rule['stats'] == expected['stats']
    assert set(rule['examples']) == {'basic', 'frost', 'plain_frost'}
    for key, row in rule['examples'].items():
        assert row['compiled'] == expected[key], key
    before, after = [rule['examples'][key] for key in ['plain_frost', 'frost']]
    plain, frost = before['compiled'], after['compiled']
    assert frost['support_ids'] == ['frost_lock'] and plain['support_ids'] == []
    assert frost['freeze_profile'] == dict(policy, enabled=True) and frost['snapshot']['freeze_policy'] == policy
    assert 'freeze_profile' not in plain and 'freeze_policy' not in plain['snapshot']
    assert plain['recipe'] == frost['recipe'] and plain['packets'] == frost['packets']
    assert frost['initial_count'] == 5 and frost['recipe']['pierce'] == 2 and frost['recipe']['slow'] == 3 and frost['cooldown'] == 4
    near(after['resolved']['total'], before['resolved']['total'] * .75)
    near(frost['mana'], plain['mana'] * 1.20)
    near(plain['mana'], 16)
    assert frost['critical'] == plain['critical']
    group_id = frost['group_id']
    owned = [uid for uid, item in raw['items'].items() if item.get('definition_id') == 'support:frost_lock']
    assert len(owned) == 1 and raw['locations'][owned[0]] == {'kind': 'skill_support', 'group_id': group_id, 'index': 2}
    support = data['supports']['frost_lock']
    assert support == {'name': '霜锁辅助', 'description': support['description'], 'skills': ['frost'], 'requires': [], 'family': 'frost_lock', 'operations': [{'op': 'primary_hit_more', 'value': -.25}, {'op': 'mana_multiplier', 'value': 1.20}]}
    gem = data['canonical']['gem_definitions']['support:frost_lock']
    assert gem['description'] == support['description'] and gem['name'] == gem['short_name'] == support['name']
    assert gem['definition_id'] == 'support:frost_lock' and gem['support_id'] == 'frost_lock' and gem['skills'] == ['frost']
    assert gem['family'] == 'frost_lock' and gem['kind'] == 'support_gem' and gem['size'] == [1, 1]
    assert rule['merchant_quote']['cost'] == {'calibration_shard': 4} and rule['merchant_quote']['ok']
    assert rule['test_offer']['available'] and rule['test_offer']['definition_id'] == 'support:frost_lock'
    assert rule['test_offer']['preview'] == dict(gem, uid='item_000001', category='')
    program = data['support_program_examples']['frost_lock']
    assert program['family'] == 'frost_lock' and program['native_recipe_eligibility'] and set(program['examples']) == {'frost'}
    pair = program['examples']['frost']
    assert pair['before']['recipe'] == pair['after']['recipe'] == frost['recipe']
    assert pair['before']['mana'] == plain['mana'] and pair['after']['mana'] == frost['mana']
    rendered = {'save-version': 47, 'vocabulary': 46, 'source-policy': 45, 'hit-multiplier': .75, 'mana-multiplier': 1.20, 'max-targets': 100, 'immunity': 1.50, 'price': 4}
    for index, rarity in enumerate(['normal', 'magic', 'rare', 'boss'], 1):
        duration = policy['duration_by_rarity'][rarity]
        state = rule['timing']['states'][rarity]
        assert state == {'target_id': index, 'rarity': rarity, 'frozen_from': 0, 'frozen_until': duration, 'immune_until': duration + 1.50, 'provenance': {'skill_id': 'frost', 'phase': 'projectile'}}
        rendered[rarity + '-duration'] = duration
        rendered[rarity + '-immune-until'] = duration + 1.50
    for key, source, amount in [('start', 'start', .5), ('delta', 'delta', .25), ('prefix', 'frozen_prefix', .1), ('active', 'active_delta', .15)]:
        near(rule['timing']['partial_frame'][source], amount)
        rendered['frame-' + key] = amount
    for key in ['plain_frost', 'frost']:
        row = rule['examples'][key]
        rendered.update({key + '-hit': row['resolved']['total'], key + '-mana': row['compiled']['mana'], key + '-count': 5, key + '-pierce': 2, key + '-slow': 3, key + '-cooldown': 4})
    # Rebuild the complete catalog from the old one using only exact additions
    # and current schema labels; historical casts and stat subtrees cannot drift.
    projected = deepcopy(old)
    projected['game_version'] = '0.73.0'
    savepaths = [('save_version',), ('canonical', 'default_build', 'version'), ('canonical', 'save_version'), ('crafting', 'calibration_shard', 'save_version'), ('currencies', 'calibration_shard', 'save_version'), ('melee_basic', 'save_version'), ('normal_gem_trading', 'schema'), ('sunwell_terrace', 'save_version'), ('town_maps', 'save_version')]
    operations = ['augment', 'elevate', 'enchant', 'recalibrate', 'reforge', 'salvage', 'targeted_reforge_critical', 'targeted_reforge_damage', 'targeted_reforge_life_leech', 'targeted_reforge_mana_leech']
    savepaths += [('crafting', operation, 'example', 'save_version') for operation in operations]
    for path in savepaths:
        replace(projected, path, 46, 47)
    projected['frost_lock'] = rule
    projected['supports']['frost_lock'] = support
    projected['support_program_examples']['frost_lock'] = program
    projected['canonical']['gem_definitions']['support:frost_lock'] = gem
    replace(projected, ('canonical', 'gem_reward', 'definition_count'), 31, 32)
    projected['skills']['frost']['compatible_supports'].append('frost_lock')
    projected['normal_gem_trading']['offers'].append({'definition_id': 'support:frost_lock', 'kind': 'support_gem', 'name': '霜锁辅助', 'cost': 4})
    projected['normal_gem_trading']['offers'].sort(key=lambda item: item['definition_id'])
    projected['town_maps']['stock']['skill_merchant'].append(rule['test_offer'])
    projected['town_maps']['stock']['skill_merchant'].sort(key=lambda item: item['id'])
    assert projected == data, list(differences(projected, data))[:12]
    assert data['precise_technique'] == old['precise_technique'] and data['glove_ring_affixes'] == old['glove_ring_affixes']
    # Preserve every old PNG, font, raw source-data file, and recorded historical
    # build/expected pair. Only one new runtime icon and its F8 copy are admitted.
    paths = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', BASE, 'assets', 'data', 'docs/reference', 'docs/qa/v070-gameplay/fixtures', 'docs/qa/v072-gameplay/fixtures'], cwd=ROOT, text=True).splitlines()
    preserved = ['docs/reference/reference.css', 'docs/reference/reference.js', 'docs/reference/art/manifest.json', 'docs/reference/source-tree-coverage.json']
    preserved += [path for path in paths if path.endswith(('.png', '.ttf', '.otf')) or path.startswith(('data/', 'docs/qa/v070-gameplay/fixtures/', 'docs/qa/v072-gameplay/fixtures/'))]
    hashes = {path: sha((ROOT / path).read_bytes()) for path in preserved}
    for path, digest in hashes.items():
        assert digest == sha(oldbytes(path)), path
    oldpngs = {path for path in paths if path.endswith('.png')}
    allpngs = {path.relative_to(ROOT).as_posix() for folder in [ROOT / 'assets', REF] for path in folder.rglob('*.png')}
    assert allpngs - oldpngs == {'assets/ui/grimoire/frost_lock.png', 'docs/reference/originals/frost_lock.png'}
    icon = (ROOT / 'assets/ui/grimoire/frost_lock.png').read_bytes()
    assert sha(icon) == ICON_HASH and icon == (REF / rule['icon_file']).read_bytes()
    assert icon[:8] == b'\x89PNG\r\n\x1a\n' and struct.unpack('>II', icon[16:24]) == (1254, 1254) and icon[25] == 6
    assert gem['icon'] == gem['icon_texture'] == rule['icon_source'] == 'res://assets/ui/grimoire/frost_lock.png'
    page, oldpage = Page(), Page()
    html = (REF / 'index.html').read_text()
    page.feed(html)
    oldpage.feed(oldbytes('docs/reference/index.html').decode())
    assert page.values.keys() == rendered.keys()
    for key, amount in rendered.items():
        near(page.values[key], amount)
        assert page.labels[key].strip() == format(amount, '.10g'), (key, page.labels[key], amount)
    assert len(page.ids) == len(set(page.ids)) and set(oldpage.ids) <= set(page.ids)
    assert set(page.ids) - set(oldpage.ids) == {'rules-frost_lock', 'supports-frost_lock'}
    for link in page.links:
        if link.startswith('#'):
            assert link[1:] in page.ids, link
        elif link and not link.startswith(('http:', 'https:', 'mailto:')):
            assert (REF / link.split('#')[0]).is_file(), link
    for asset in page.assets:
        assert not asset.startswith(('http:', 'https:')) and (REF / asset).is_file(), asset
    for wording in ['正的实际冰伤盾血损失', '当前命中结算边界elapsed', '不追溯取消', '接触攻击计时', '双响局部时钟', '保留原锁定圆心', '冻结前缀', '护盾恢复继续', '不刷新、不叠加', '严格decode_v46', '不赠宝石或碎片']:
        assert wording in html, wording
    changes = list(differences(old, data))
    report = {'passed': True, 'baseline_commit': subprocess.check_output(['git', 'rev-parse', BASE], cwd=ROOT, text=True).strip(),
              'reused_actual_main_fixture_count': 1, 'exact_current_casts_checked': 3, 'historical_main_casts_preserved': 24,
              'old_catalog_preserved_except_explicit_projection': True, 'source_policy_preserved': 45, 'equipment_vocabulary_preserved': 46,
              'normal_reward_definition_count_preserved': 26, 'source_coverage_byte_identical': True,
              'authoritative_html_values_and_labels_checked': len(rendered), 'old_html_anchors_preserved': len(oldpage.ids), 'html_unique_ids': len(page.ids),
              'new_html_anchors': sorted(set(page.ids) - set(oldpage.ids)), 'all_anchor_and_local_file_links_valid': True,
              'old_pngs_preserved': len(oldpngs), 'new_pngs': sorted(allpngs - oldpngs), 'icon_sha256': ICON_HASH,
              'catalog_sha256': sha((REF / 'catalog.json').read_bytes()), 'html_sha256': sha((REF / 'index.html').read_bytes()),
              'fixtures': acceptance['fixtures'], 'unchanged_files': hashes,
              'exact_allowed_catalog_changed_paths': [{'kind': kind, 'path': list(path)} for kind, path, _, _ in changes],
              'historical_fixed_gate_audit': {'docs/qa/v070-reference/check-reference.py': 'Immutable v70/schema45 receipt; current exporter uses validated45→46→47 memory migration with exact stats and casts', 'docs/qa/v072-reference/check-reference.py': 'Immutable v72/schema46 receipt; current exporter uses validated46→47 memory migration with exact stats, resistances and casts'},
              'scope': 'One Godot export and Python build/determinism/preservation; no new Main, import, native launch or packaging'}
    with (QA / 'v072-preservation.json').open('x') as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2)
        stream.write('\n')
    print(json.dumps({key: value for key, value in report.items() if key not in ['fixtures', 'unchanged_files', 'exact_allowed_catalog_changed_paths']}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Bounded v72 Main-fixture projection, rendered values, and exact v71 preservation."""
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
BASE = 'bf794d05f2468ccda22bb170a643839b5aba880e'
NEW = ['glove_accuracy', 'ring_emberward', 'ring_rimeward', 'ring_stormward']
NAMES = ['precise-equal', 'precise-above', 'glove-finesse', 'rings-triple-default', 'rings-source-cap83']
GLOVE, RING = 'nine_slot_threaded_gloves', 'nine_slot_etched_ring'
POOL = 'build_nine_slot_v46'


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
        if 'data-glove-ring-value' in attrs:
            key = attrs['data-glove-ring-value']
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
    rule = data['glove_ring_affixes']
    assert data['game_version'] == '0.72.0' and data['save_version'] == rule['minimum_save_version'] == rule['equipment_vocabulary'] == 46
    assert rule['source_policy'] == 45 and rule['new_images'] == []
    assert set(rule['new_families']) == set(NEW) and rule['base_ids'] == [GLOVE, RING]
    assert (rule['existing_slot_count'], rule['existing_random_base_count'], rule['existing_fixed_item_count']) == (9, 15, 9)
    for new, source in zip(NEW[1:], ['emberward', 'rimeward', 'stormward']):
        family = deepcopy(rule['new_families'][new])
        original = {k: v for k, v in old['affixes'][source].items() if k not in ['pools', 'eligible_bases', 'formatted_examples', 'formatted_ranges', 'affected_skills', 'other_consumers']}
        original.update(slots=['ring'], allowed_base_ids=[RING])
        assert family == original, new
    accuracy = rule['new_families']['glove_accuracy']
    assert {k: accuracy[k] for k in ['name', 'label', 'stat', 'kind', 'unit', 'group', 'slots', 'allowed_base_ids']} == {'name': '精瞄', 'label': '命中值', 'stat': 'accuracy', 'kind': 'prefix', 'unit': 'flat', 'group': 'accuracy_rating', 'slots': ['gloves'], 'allowed_base_ids': [GLOVE]}
    assert accuracy['tiers'] == [dict(tier=i, level=level, weight=weight, min=lo, max=hi) for i, level, weight, lo, hi in [(1, 1, 100, 35, 60), (2, 8, 60, 70, 110), (3, 16, 30, 120, 160)]]
    for key in NEW:
        family = data['affixes'][key]
        assert {k: v for k, v in family.items() if k not in ['pools', 'eligible_bases', 'formatted_examples', 'formatted_ranges', 'affected_skills', 'other_consumers']} == rule['new_families'][key]
        assert family['affected_skills'] == family['other_consumers'] == []
        assert family['pools'] == [POOL] and family['eligible_bases'] == ([GLOVE] if key == NEW[0] else [RING])
    acceptance = json.loads((ROOT / 'docs/qa/v072-gameplay/acceptance.json').read_text())
    assert acceptance['passed'] and set(rule['examples']) == set(NAMES)
    rendered = {'save-version': 46, 'vocabulary': 46, 'source-policy': 45, 'slots': 9, 'bases': 15, 'fixed': 9}
    ratios = set()
    for name in NAMES:
        row = rule['examples'][name]
        raw = json.loads((ROOT / row['fixture']).read_text())
        expected = json.loads((ROOT / row['expected_fixture']).read_text())
        assert row['fixture'] == f'docs/qa/v072-gameplay/fixtures/{name}.json'
        assert row['expected_fixture'] == f'docs/qa/v072-gameplay/fixtures/{name}-expected.json'
        for pathkey, hashkey, suffix in [('fixture', 'fixture_sha256', '.json'), ('expected_fixture', 'expected_sha256', '-expected.json')]:
            assert sha((ROOT / row[pathkey]).read_bytes()) == row[hashkey] == acceptance['fixtures'][name + suffix]
        assert raw['version'] == 46 and row['stats'] == expected['stats'] and row['resistance'] == expected['resistance']
        assert row['talents'] == raw['talents'] and row['progress'] == raw['progress']
        assert row['whole_build_valid'] and row['matches_actual_main'] and row['save_attempts'] == 0
        for skill in ['basic', 'cleave', 'tornado']:
            assert row['casts'][skill] == expected[skill], (name, skill)
        for slot, item in row['equipment'].items():
            assert item['item'] == raw['items'][item['uid']]
            assert raw['locations'][item['uid']] == {'kind': 'equipment', 'slot_id': slot}
        profile = row['casts']['basic'].get('precise_technique_profile', {})
        rendered.update({name + '-accuracy': row['stats']['accuracy'], name + '-life': row['stats']['max_health'], name + '-more': profile.get('attack_more', 0), name + '-saves': 0})
        ratios.add(name + '-more')
        if name.startswith('rings-'):
            for element in ['fire', 'cold', 'lightning']:
                for field in ['raw_resistances', 'maximum_resistances', 'effective_resistances']:
                    key = name + '-' + element + '-' + field
                    rendered[key] = row['resistance'][field][element]
                    ratios.add(key)
    equal, above = [rule['examples'][name] for name in NAMES[:2]]
    assert equal['stats']['accuracy'] == equal['stats']['max_health']
    assert above['stats']['accuracy'] > above['stats']['max_health']
    assert equal['casts']['basic']['precise_technique_profile']['attack_more'] == 0
    assert above['casts']['basic']['precise_technique_profile']['attack_more'] == .4
    for row in [equal, above]:
        assert row['casts']['basic']['precise_technique_profile']['cannot_deal_critical_strikes']
    resistance = rule['examples']['rings-triple-default']['resistance']
    for element, amount in [('fire', .9), ('cold', .75), ('lightning', .75)]:
        near(resistance['raw_resistances'][element], amount)
        assert resistance['maximum_resistances'][element] == resistance['effective_resistances'][element] == .75
    capped = rule['examples']['rings-source-cap83']['resistance']
    assert capped['maximum_resistances'] == dict.fromkeys(['fire', 'cold', 'lightning'], .83)
    for element in capped['maximum_resistances']:
        near(capped['effective_resistances'][element], min(.83, capped['raw_resistances'][element]))
    probes = rule['accuracy_probes']
    assert probes['baseline_accuracy'] == 284 and probes['evasion'] == 1600 and probes['baseline_chance'] == .77
    rendered.update({'baseline-accuracy': 284, 'evasion': 1600, 'baseline-chance': .77})
    ratios.add('baseline-chance')
    for row, chances in zip(probes['tiers'], [(.80, .82), (.83, .86), (.87, .89)]):
        tier = int(row['tier'])
        assert row['level'] == [1, 8, 16][tier - 1] and row['weight'] == [100, 60, 30][tier - 1]
        for end, chance in zip(['min', 'max'], chances):
            endpoint = row['endpoints'][end]
            assert endpoint['flat_accuracy'] == accuracy['tiers'][tier - 1][end]
            assert endpoint['accuracy'] == 284 + endpoint['flat_accuracy'] and endpoint['chance'] == chance
            for field, source in [('flat', 'flat_accuracy'), ('accuracy', 'accuracy'), ('chance', 'chance')]:
                key = f't{tier}-{field}-{end}'
                rendered[key] = endpoint[source]
                if field == 'chance':
                    ratios.add(key)
    # Allow only enumerated version/current-profile metadata and the new content.
    projected = deepcopy(old)
    projected['glove_ring_affixes'] = rule
    projected['game_version'] = '0.72.0'
    savepaths = [('save_version',), ('canonical', 'default_build', 'version'), ('canonical', 'save_version'), ('crafting', 'calibration_shard', 'save_version'), ('currencies', 'calibration_shard', 'save_version'), ('melee_basic', 'save_version'), ('normal_gem_trading', 'schema'), ('sunwell_terrace', 'save_version'), ('town_maps', 'save_version')]
    operations = ['augment', 'elevate', 'enchant', 'recalibrate', 'reforge', 'salvage', 'targeted_reforge_critical', 'targeted_reforge_damage', 'targeted_reforge_life_leech', 'targeted_reforge_mana_leech']
    savepaths += [('crafting', operation, 'example', 'save_version') for operation in operations]
    for path in savepaths:
        replace(projected, path, 45, 46)
    for chapter in ['ambush', 'inward_pull', 'iron_reflexes', 'physical_fire_conversion', 'precise_technique', 'resolute_technique', 'zealots_oath']:
        replace(projected, (chapter, 'equipment_vocabulary'), 39, 46)
    for chapter in ['elemental_defense_affixes', 'defense_rating_affixes']:
        replace(projected, (chapter, 'vocabulary'), 39, 46)
    newpool = deepcopy(old['equipment_pools']['build_nine_slot_v27'])
    newpool['affix_ids'] += NEW
    newpool['min_save_version'] = 46
    assert rule['pool_id'] == POOL and rule['pool'] == newpool
    projected['equipment_pools'][POOL] = newpool
    newprofile = deepcopy(old['loot_profiles']['canonical_v39'])
    assert newprofile[4] == {'pool_id': 'build_nine_slot_v27', 'weight': 30}
    newprofile[4]['pool_id'] = POOL
    projected['loot_profiles']['canonical_v46'] = newprofile
    assert rule['loot_profile_id'] == 'canonical_v46' and rule['loot_profile'] == newprofile
    for path in [('current_loot_profile_id',), ('forgeblade', 'current_loot_profile_id'), ('elemental_defense_affixes', 'loot_profile_id'), ('defense_rating_affixes', 'loot_profile_id')]:
        replace(projected, path, 'canonical_v39', 'canonical_v46')
    for path in [('current_loot_profile',), ('forgeblade', 'current_loot_profile'), ('elemental_defense_affixes', 'loot_profile'), ('defense_rating_affixes', 'loot_profile')]:
        replace(projected, path, old['loot_profiles']['canonical_v39'], newprofile)
    for key in old['equipment_pools']['build_nine_slot_v27']['affix_ids']:
        projected['affixes'][key]['pools'].append(POOL)
    for key in NEW:
        projected['affixes'][key] = data['affixes'][key]
    for base, ids in [(GLOVE, NEW[:1]), (RING, NEW[1:])]:
        projected['equipment'][base]['eligible_affixes'] += ids
        projected['crafting']['calibration_shard']['rules']['eligible_families_by_base'][base] += ids
    projected['crafting']['calibration_shard']['rules']['affix_ids'] += NEW
    replace(projected, ('crafting', 'calibration_shard', 'rules', 'catalog_vocabulary'), 39, 46)
    for operation in operations[6:]:
        replace(projected, ('crafting', operation, 'catalog_vocabulary'), 39, 46)
    replace(projected, ('elemental_resistance_caps', 'equipment', 'equipment_cold_sources'), ['rimeward'], ['rimeward', 'ring_rimeward'])
    replace(projected, ('elemental_resistance_caps', 'equipment', 'equipment_lightning_sources'), ['stormward'], ['stormward', 'ring_stormward'])
    assert projected == data, list(differences(projected, data))[:12]
    # Every historical example remains equal; v70 only receives a current
    # equipment-vocabulary label. Its schema45 source files stay untouched.
    assert data['precise_technique']['examples'] == old['precise_technique']['examples']
    preserved = ['docs/reference/reference.css', 'docs/reference/reference.js', 'docs/reference/art/manifest.json', 'docs/reference/source-tree-coverage.json', 'docs/qa/v070-gameplay/acceptance.json']
    paths = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', BASE, 'assets', 'data', 'docs/reference', 'docs/qa/v070-gameplay/fixtures'], cwd=ROOT, text=True).splitlines()
    preserved += [path for path in paths if path.endswith('.png') or path.startswith(('data/', 'docs/qa/v070-gameplay/fixtures/'))]
    hashes = {path: sha((ROOT / path).read_bytes()) for path in preserved}
    for path, digest in hashes.items():
        assert digest == sha(oldbytes(path)), path
    oldpngs = sorted(path for path in paths if path.endswith('.png'))
    assert oldpngs == sorted(path.relative_to(ROOT).as_posix() for folder in [ROOT / 'assets', REF] for path in folder.rglob('*.png'))
    page, oldpage = Page(), Page()
    html = (REF / 'index.html').read_text()
    page.feed(html)
    oldpage.feed(oldbytes('docs/reference/index.html').decode())
    assert page.values.keys() == rendered.keys()
    for key, amount in rendered.items():
        near(page.values[key], amount)
        label = f'{amount * 100:.0f}%' if key in ratios else format(amount, '.10g')
        assert page.labels[key].strip() == label, (key, page.labels[key], label)
    assert len(page.ids) == len(set(page.ids)) and set(oldpage.ids) <= set(page.ids)
    assert set(page.ids) - set(oldpage.ids) == {'rules-glove_ring_affixes'} | {'affixes-' + key for key in NEW}
    for link in page.links:
        if link.startswith('#'):
            assert link[1:] in page.ids, link
        elif link and not link.startswith(('http:', 'https:', 'mailto:')):
            assert (REF / link.split('#')[0]).is_file(), link
    for asset in page.assets:
        assert not asset.startswith(('http:', 'https:')) and (REF / asset).is_file(), asset
    for wording in ['A严格大于最大生命', '九条完美后缀', '不是正常预期掉落', '只放大一次', '不是补不存在的空槽', '命中率变化不是伤害MORE或DPS']:
        assert wording in html, wording
    changes = list(differences(old, data))
    report = {'passed': True, 'baseline_commit': BASE, 'reused_actual_main_fixture_count': 5, 'exact_current_casts_checked': 15, 'historical_v070_casts_preserved': 9,
              'old_catalog_preserved_except_explicit_projection': True, 'source_coverage_byte_identical': True, 'source_policy_preserved': 45,
              'authoritative_html_values_and_labels_checked': len(rendered), 'old_html_anchors_preserved': len(oldpage.ids), 'html_unique_ids': len(page.ids),
              'new_html_anchors': sorted(set(page.ids) - set(oldpage.ids)), 'all_anchor_and_local_file_links_valid': True,
              'old_asset_pngs_preserved': len([p for p in oldpngs if p.startswith('assets/')]), 'old_reference_pngs_preserved': len([p for p in oldpngs if p.startswith('docs/reference/')]),
              'catalog_bytes': (REF / 'catalog.json').stat().st_size, 'catalog_sha256': sha((REF / 'catalog.json').read_bytes()), 'html_sha256': sha((REF / 'index.html').read_bytes()),
              'fixtures': acceptance['fixtures'], 'unchanged_files': hashes,
              'exact_allowed_catalog_changed_paths': [{'kind': kind, 'path': list(path)} for kind, path, _, _ in changes],
              'historical_fixed_gate_audit': {'docs/qa/v070-reference/check-reference.py': 'Historical v0.70/schema45/equipment39 receipt; immutable, superseded for current output by this exact projection', 'docs/qa/v071-reference/check-reference.py': 'Historical v0.71/schema45 receipt; immutable, preserved mist-skitter subtree exactly', 'tests/source_critical_reference_test.gd': 'Historical v0.39/schema24 fixed gate, not a current whole-reference gate'},
              'scope': 'One export/build/check; no new Main, historical full-suite, native launch, import or packaging'}
    with (QA / 'v071-preservation.json').open('x') as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2)
        stream.write('\n')
    print(json.dumps({key: value for key, value in report.items() if key not in ['fixtures', 'unchanged_files', 'exact_allowed_catalog_changed_paths']}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()

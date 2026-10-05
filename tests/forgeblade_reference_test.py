#!/usr/bin/env python3
"""Focused v55 reference: real items/compiler, exact historical projection and assets."""
import hashlib
import json
import math
import re
from collections import Counter
from copy import deepcopy
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REF = ROOT/'docs/reference'
QA = ROOT/'docs/qa/v055-reference'
FAMILIES = ['whetstone_edge', 'tempered_edge', 'deepwell', 'wellturn',
            'global_critical_chance', 'global_critical_multiplier']
LOCAL = FAMILIES[:2]
CRIT = FAMILIES[-2:]


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                    separators=(',', ':')).encode()).hexdigest()


def near(actual, expected):
    assert math.isfinite(actual) and abs(actual-expected) <= max(1e-9, 1e-12*abs(expected)), (actual, expected)


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids, self.links, self.assets, self.values, self.article = [], [], [], {}, None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if 'id' in attrs: self.ids.append(attrs['id'])
        if tag == 'article': self.article = attrs.get('id')
        if tag == 'a' and 'href' in attrs: self.links.append(attrs['href'])
        if tag == 'img' and 'src' in attrs: self.assets.append(attrs['src'])
        if 'data-forgeblade-value' in attrs:
            assert self.article == 'rules-forgeblade'
            key = attrs['data-forgeblade-value']
            assert key not in self.values
            self.values[key] = float(attrs['data-value'])

    def handle_endtag(self, tag):
        if tag == 'article': self.article = None


def historical_projection(data, baseline):
    projected = deepcopy(data)
    for path in baseline['new_paths']:
        at = projected
        for key in path[:-1]: at = at[key]
        assert (0 <= path[-1] < len(at)) if isinstance(at,list) else path[-1] in at, path
        del at[path[-1]]
    for change in baseline['approved_changes']:
        path = change['path']
        at = projected
        for key in path[:-1]: at = at[key]
        assert at[path[-1]] == change['after'], path
        at[path[-1]] = change['before']
    return projected


def main():
    data = json.loads((REF/'catalog.json').read_text())
    source = (REF/'index.html').read_text()
    baseline = json.loads((QA/'v054-reference-baseline.json').read_text())
    blade = data['forgeblade']
    page = Page(); page.feed(source)
    assert data['game_version'] == '0.55.0' and data['save_version'] == 34
    assert blade['save_version'] == 34 and blade['base_id'] == 'forgeblade'
    assert blade['base'] == {k: v for k, v in data['equipment']['forgeblade'].items()
                             if k not in ['pool', 'eligible_affixes', 'stats_text', 'normal_instance', 'normal_definition']}
    assert blade['base']['size'] == [1, 3] and blade['base']['stats'] == {}
    assert blade['pool'] == data['equipment_pools']['forgeblade_v34']
    assert blade['pool']['affix_ids'] == FAMILIES and blade['pool']['base_ids'] == ['forgeblade']
    assert blade['pool']['min_save_version'] == 34
    assert blade['local_consumers'] == {'cleave': ['direct']}
    assert set(data['equipment']['forgeblade']['eligible_affixes']) == set(FAMILIES)
    assert data['equipment']['forgeblade']['normal_instance']['base_id'] == 'forgeblade'
    assert data['equipment']['ashwood_bow']['normal_instance']['base_id'] == 'ashwood_bow'
    for key, family in blade['families'].items():
        assert family['tiers'] == data['affixes'][key]['tiers']
        assert [t['level'] for t in family['tiers']] == [1, 8, 16]
        assert [t['weight'] for t in family['tiers']] == [100, 60, 30]
        assert family['kind'] == ('prefix' if key in FAMILIES[:3] else 'suffix')
    assert len(set(f['group'] for f in blade['families'].values())) == 6
    expected_sets = {'normal': {0: 1}, 'magic': {1: 6, 2: 9}, 'rare': {4: 15, 5: 6, 6: 1}}
    rendered = {'save-version': 34}
    for rarity, expected in expected_sets.items():
        sets = blade['legal_family_sets'][rarity]
        assert dict(Counter(map(len, sets))) == expected
        assert len({tuple(ids) for ids in sets}) == len(sets)
        for ids in sets:
            kinds = Counter(blade['families'][key]['kind'] for key in ids)
            assert kinds['prefix'] <= data['equipment_rarities'][rarity]['max_prefixes']
            assert kinds['suffix'] <= data['equipment_rarities'][rarity]['max_suffixes']
        rendered.update({f'family-sets-{rarity}-{count}': total for count, total in expected.items()})
    expected_samples = {'normal': (4, 61.6, .05, 1.5), 'dual_t1_min': (5.5, 65.8, .05, 1.5),
                        'dual_t1_max': (6.9, 69.72, .05, 1.5), 'six_t1_max': (6.9, 69.72, .06, 1.57),
                        'six_t3_max': (13, 86.8, .07, 1.65)}
    packet_count = 0
    for key, (weapon, raw, chance, multiplier) in expected_samples.items():
        example = blade['examples'][key]; instance = example['instance']; hit = example['casts']['cleave']['hits']['direct']
        assert instance['base_id'] == 'forgeblade'
        assert instance['rarity'] == ('normal' if key == 'normal' else 'rare')
        assert [a['id'] for a in instance['affixes']] in blade['legal_family_sets'][instance['rarity']]
        for affix in instance['affixes']:
            tier = blade['families'][affix['id']]['tiers'][affix['tier']-1]
            assert tier['min'] <= affix['value'] <= tier['max'] and instance['item_level'] >= tier['level']
        assert example['stats']['damage'] == 18
        assert 'weapon_added_physical' not in example['stats'] and 'weapon_physical_increased' not in example['stats']
        profile = example['definition']['weapon_profile']
        near((profile['base']['physical']+profile['flat']['physical'])*(1+profile['increased']['physical']), weapon)
        near(example['weapon']['components']['physical'], weapon)
        near(hit['local_contribution'], weapon*2.8)
        near(hit['packet']['assembly']['intrinsic']['physical'], 50.4)
        near(sum(hit['packet']['base'].values()), raw)
        near(hit['resolved']['total'], raw)
        near(hit['expected_zero_defense'], raw*(1+chance*(multiplier-1)))
        assert set(example['casts']) == set(data['skills']) | {'basic'}
        for skill, cast in example['casts'].items():
            for role, part in cast['hits'].items():
                packet_count += 1
                near(part['critical']['chance'], chance)
                near(part['critical']['multiplier'], multiplier)
                if skill != 'cleave' or role != 'direct':
                    assert part['local_contribution'] == 0 and part['packet'] == part['no_local_packet']
                if key == 'six_t3_max': rendered[f'scope-{skill}-{role}'] = part['local_contribution']
        rendered.update({key+'-w': weapon, key+'-contribution': weapon*2.8, key+'-raw': raw,
                         key+'-resolved': raw, key+'-chance': chance, key+'-multiplier': multiplier,
                         key+'-expected': raw*(1+chance*(multiplier-1))})
    full_stats = blade['examples']['six_t3_max']['definition']['stats']
    assert full_stats == {'max_mana': 22, 'mana_regen_increased': .14,
                          'crit_chance_increased': .4, 'crit_multiplier_add': .15}
    rendered.update({'global-max-mana': 22, 'global-mana-regen': .14})
    profile = blade['current_loot_profile']
    assert blade['current_loot_profile_id'] == data['current_loot_profile_id'] == 'canonical_v34'
    assert profile == data['current_loot_profile'] == data['loot_profiles']['canonical_v34']
    assert [r['weight'] for r in profile] == [25, 20, 10, 10, 30, 5]
    for row in profile: rendered['loot-'+row['pool_id']] = row['weight']
    assert set(blade['crafting']) == {'salvage','recalibrate','enchant','elevate','augment','reforge',
                                      'targeted_reforge_damage','targeted_reforge_critical',
                                      'targeted_reforge_life_leech','targeted_reforge_mana_leech'}
    for operation, row in blade['crafting'].items():
        if operation in ['targeted_reforge_life_leech', 'targeted_reforge_mana_leech']:
            assert not row['quote']['ok'] and not row['rare_quote']['ok']
            assert row['quote']['code'] == row['rare_quote']['code'] == 'no_legal_target'
            assert row['eligible_families'] == [] and 'planned_instance' not in row
        else:
            assert row['quote']['ok'], (operation, row['quote'])
        if operation in ['targeted_reforge_damage', 'targeted_reforge_critical']:
            assert row['eligible_families'] == (LOCAL if operation.endswith('damage') else CRIT)
            for rarity, field, cost in [('magic','quote',16),('rare','rare_quote',40)]:
                assert row[field]['ok'] and row[field]['cost'] == {'calibration_shard':cost}
                rendered[f'{operation}-{rarity}-cost'] = cost
            assert any(a['id'] in row['eligible_families'] for a in row['planned_instance']['affixes'])
    migration = blade['migration']
    assert migration['from_version'] == 33 and migration['to_version'] == 34
    assert migration['changed_fields'] == ['version'] and migration['items_preserved'] and migration['talents_preserved']
    assert not migration['fresh_has_forgeblade'] and migration['old_vocabulary_rejects_forgeblade']
    assert set(page.values) == set(rendered), (set(page.values)-set(rendered), set(rendered)-set(page.values))
    for key, expected in rendered.items(): near(page.values[key], expected)
    assert len(page.ids) == len(set(page.ids)), 'Duplicate HTML identifiers'
    assert set(baseline['article_ids']) <= set(page.ids), 'A historical rule/card was removed'
    for url in page.links:
        if url.startswith('#'): assert url[1:] in page.ids, url
    for url in page.assets:
        assert not url.startswith(('http:', 'https:', 'data:')) and (REF/url).is_file(), url
    assert blade['icon_file'] in page.assets
    assert (REF/blade['icon_file']).read_bytes() == (ROOT/blade['icon_source'].removeprefix('res://')).read_bytes()
    images = {p.relative_to(REF).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in REF.rglob('*.png')}
    assert len(baseline['image_sha256']) == 67
    assert set(images) == set(baseline['image_sha256']) | {blade['icon_file']}
    for key, expected in baseline['image_sha256'].items(): assert images[key] == expected, key
    assert digest(data['source_tree']) == baseline['source_tree_sha256'], 'All source structure and execution stay exact'
    assert hashlib.sha256((REF/'source-tree-coverage.json').read_bytes()).hexdigest() == baseline['source_coverage_sha256']
    assert digest(historical_projection(data, baseline)) == baseline['catalog_semantic_sha256'], 'Unapproved legacy catalog drift'
    for text in ['不是默认角色伤害或实战DPS', '原字节备份', '旧schema注入forgeblade整份拒绝', '全局暴击仍作用于攻击、法术及独立secondary']:
        assert text in source, text
    print(f'Forgeblade reference: PASS; {len(expected_samples)} legal fixtures; {packet_count} real packets; '
          f'{len(rendered)} rendered values; 6-family pool; exact v54 projection; all source execution; 67 old + 1 original PNG')


if __name__ == '__main__':
    main()

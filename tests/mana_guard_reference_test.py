#!/usr/bin/env python3
"""v58 production resource evidence, source gates, rendered values and exact frozen-v57 projection."""
import hashlib
import json
import math
import re
from copy import deepcopy
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REF = ROOT / 'docs/reference'
QA = ROOT / 'docs/qa/v058-reference'
STAT = 'damage_taken_from_mana_before_life'
FIELDS = ['damage_total', 'shield_spent', 'mana_spent', 'health_lost', 'overkill',
          'remaining_shield', 'remaining_mana', 'remaining_health']


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
        if tag == 'a': self.links.append(attrs.get('href', ''))
        if tag in ('img', 'script', 'link'):
            url = attrs.get('src', attrs.get('href', ''))
            if url: self.assets.append(url)
        if 'data-mana-guard-value' in attrs:
            assert self.article == 'rules-mana_guard'
            key = attrs['data-mana-guard-value']
            assert key not in self.values, key
            self.values[key] = float(attrs['data-value'])

    def handle_endtag(self, tag):
        if tag == 'article': self.article = None


def historical_projection(data, baseline):
    projected = deepcopy(data)
    for path in baseline['new_paths']:
        at = projected
        for key in path[:-1]: at = at[key]
        assert path[-1] in at, path
        if path != ['mana_guard']:
            assert path[-1] == STAT and at[path[-1]] == 0, path
        del at[path[-1]]
    for change in baseline['approved_changes']:
        path = change['path']
        assert change['category'] in {'version', 'source_execution', 'display_metadata'}, change
        at = projected
        for key in path[:-1]: at = at[key]
        assert at[path[-1]] == change['after'], path
        at[path[-1]] = change['before']
    return projected


def main():
    data = json.loads((REF/'catalog.json').read_text())
    source = (REF/'index.html').read_text()
    baseline = json.loads((QA/'v057-reference-baseline.json').read_text())
    guard, tree = data['mana_guard'], data['source_tree']
    page = Page(); page.feed(source)
    assert data['game_version'] == '0.58.0' and data['save_version'] == guard['minimum_save_version'] == 35
    assert guard['stat'] == STAT
    assert guard['source_version'] == tree['source_version'] == '3.29.1'
    assert guard['source_sha256'] == tree['source_sha256']
    assert guard['profile'] == {'ok': True, 'reason': '', 'enabled': True, 'fraction': .4}
    assert guard['disabled_profile'] == {'ok': True, 'reason': '', 'enabled': False, 'fraction': 0}
    node = guard['node']
    assert node['id'] == '34098' and node['name'] == tree['nodes']['34098']['name'] == 'Mind Over Matter'
    assert node['source_lines'] == tree['nodes']['34098']['stats'] == ['40% of Damage is taken from Mana before Life']
    assert node['execution'] == tree['nodes']['34098']['execution']
    assert node['execution']['status'] == 'full' and node['legacy_execution']['status'] == 'unsupported'
    assert node['execution']['grants'] == [{'stat': STAT, 'mode': 'flat', 'value': .4}]
    assert guard['new_complete_ordinary_nodes'] == ['34098']
    assert guard['new_mastery_effect_ids'] == guard['new_images'] == []
    assert set(guard['blocked_matching_nodes']) == {'42144', '922'}
    for node_id, fraction in [('42144', .08), ('922', .1)]:
        blocked = guard['blocked_matching_nodes'][node_id]
        current = tree['nodes'][node_id]
        assert blocked['execution'] == current['execution']
        assert blocked['source_lines'] == current['stats']
        assert current['execution']['status'] == 'partial' and not current['standard_graph']
        assert current['execution']['unsupported']
        grants = [g for g in current['execution']['grants'] if g['stat'] == STAT]
        assert len(grants) == 1 and grants[0]['mode'] == 'flat'
        near(grants[0]['value'], fraction)
    matching = {node_id for node_id, n in tree['nodes'].items()
                if any(re.fullmatch(r'\d+% of Damage is taken from Mana before Life', line) for line in n['stats'])}
    assert matching == {'34098', '42144', '922'}
    for node_id in matching:
        article = re.search(r'<article\b[^>]*id="source_passives-'+node_id+r'"[^>]*>.*?</article>', source, re.S).group()
        assert 'rules-mana_guard' in article
        assert ('完整效果已接入' in article) == (node_id == '34098')
    expected = {'full_mana': (0, 40, 60, 0), 'low_mana': (0, 10, 90, 0),
                'partial_shield': (30, 28, 42, 0), 'full_shield': (100, 0, 0, 0),
                'empty_mana': (0, 0, 100, 0), 'lethal': (0, 10, 20, 70)}
    assert set(guard['examples']) == set(expected)
    rendered = {'fraction': .4, 'save-version': 35, 'disabled-fraction': 0}
    for key, values in expected.items():
        example = guard['examples'][key]
        for kind in ['hit', 'burn']:
            result = example[kind]
            assert result['ok'] and result['actor'] == 'player'
            near(result['damage_total'], 100)
            for field, value in zip(['shield_spent', 'mana_spent', 'health_lost', 'overkill'], values):
                near(result[field], value)
            near(sum(result[k] for k in ['shield_spent', 'mana_spent', 'health_lost', 'overkill']), 100)
            for pool, spent in [('shield', 'shield_spent'), ('mana', 'mana_spent'), ('health', 'health_lost')]:
                near(result['remaining_'+pool], example['input'][pool]-result[spent])
            rendered.update({key+'-'+kind+'-'+field: result[field] for field in FIELDS})
        assert {f: example['hit'][f] for f in FIELDS} == {f: example['burn'][f] for f in FIELDS}
    mixed = guard['mixed_mitigation_example']
    for field, key, value in [('damage_total','damage',258.75), ('shield_spent','shield',50),
                              ('mana_spent','mana',83.5), ('health_lost','health',125.25)]:
        near(mixed[field], value); rendered['mixed-'+key] = value
    assert mixed['effective_resistances']['lightning'] == .75
    assert set(guard['zero_cases']) == {'legacy_hit', 'source_hit', 'burn'}
    for row in guard['zero_cases'].values():
        assert row['omitted'] == row['explicit_zero'] and row['variant_bytes_equal']
        assert 'mana_spent' not in row['omitted'] and 'remaining_mana' not in row['omitted']
        near(row['omitted']['shield_spent'], 30); near(row['omitted']['health_lost'], 70)
    classes = {row['class_id']: row for row in guard['class_paths']}
    assert set(classes) == set(range(7))
    for class_id, row in classes.items():
        assert row['allocated'][0] == tree['starts'][class_id]['node_id'] and row['allocated'][-1] == '34098'
        assert len(set(row['allocated'])) == len(row['allocated'])
        assert row['whole_build_valid'] and row['legacy34_rejected'] and row['save_attempts'] == 0
        assert row['profile'] == guard['profile'] and row['stats'][STAT] == .4
        assert row['points_spent'] == len(row['allocated'])-1
        assert row['required_level'] == max(1, row['points_spent']-4)
        for before, after in zip(row['allocated'], row['allocated'][1:]):
            assert after in tree['nodes'][before]['neighbors']
            assert tree['nodes'][after]['execution']['status'] == 'full'
        rendered.update({f'route-{class_id}-points': row['points_spent'], f'route-{class_id}-level': row['required_level'],
                         f'route-{class_id}-fraction': .4})
    assert classes[3]['points_spent'] == classes[5]['points_spent'] == 7
    assert classes[0]['points_spent'] == 11
    assert guard['migration_example'] == {'from_version':34, 'to_version':35, 'changed_fields':['version'],
                                          'granted_items':0, 'granted_points':0}
    assert set(page.values) == set(rendered), (set(page.values)-set(rendered), set(rendered)-set(page.values))
    for key, value in rendered.items(): near(page.values[key], value)
    assert len(page.ids) == len(set(page.ids))
    assert set(baseline['article_ids']) <= set(page.ids)
    for url in page.links:
        if url.startswith('#'): assert url[1:] in page.ids, url
        elif url and not url.startswith(('https://', 'http://')): assert (REF/url.split('#')[0]).is_file(), url
    for url in page.assets:
        assert not url.startswith(('http:', 'https:', 'data:', '//')) and (REF/url).is_file(), url
    for field, base, expected_count in [('image_sha256', REF, 68), ('material_sha256', ROOT, 61)]:
        assert len(baseline[field]) == expected_count
        actual = {p.relative_to(base).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in (REF if field == 'image_sha256' else ROOT/'assets').rglob('*.png')}
        assert actual == baseline[field], field
    assert len([url for url in page.assets if url.endswith('.png')]) == 68
    projection = historical_projection(data, baseline)
    assert set(projection) == set(baseline['section_sha256'])
    for key, expected_hash in baseline['section_sha256'].items():
        assert digest(projection[key]) == expected_hash, 'Unapproved v57 catalog drift: '+key
    assert digest(projection) == baseline['catalog_semantic_sha256']
    assert data['current_loot_profile_id'] == 'canonical_v34'
    for text in ['静态资源预算不是实战DPS', '魔力不足由生命承担', '不是魔力返还', 'mana_spent独立于health_lost',
                 '未宣称通过交互逐点分配', '新35文件不宣称与旧34文件字节相同', '心灵升华']:
        assert text in source, text
    print(f'Mana guard reference: PASS; {len(rendered)} production-rendered values; 12 hit/burn cases; 3 zero Variant-byte controls; '
          f'7 validated source routes; only 34098 fully opens; exact frozen-v57 projection; 61 materials and 68 images unchanged')


if __name__ == '__main__':
    main()

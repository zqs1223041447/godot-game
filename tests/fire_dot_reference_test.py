#!/usr/bin/env python3
"""Focused schema32 reference: production evidence, exact source scope and old data."""
import hashlib
import json
import math
import re
from copy import deepcopy
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REF = ROOT / 'docs/reference'
QA = ROOT / 'docs/qa/v053-reference'
EXPECTED = {'4713': .04, '5916': .06, '13559': .05, '31462': .05,
            '54396': .04, '2550': .10, '11924': .10, '29049': .12}


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                    separators=(',', ':')).encode()).hexdigest()


def near(actual, expected):
    assert math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-10), (actual, expected)


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = []
        self.article = None
        self.links = []
        self.assets = []
        self.values = {}

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if 'id' in attrs:
            self.ids.append(attrs['id'])
        if tag == 'article':
            self.article = attrs.get('id')
        if tag == 'a':
            self.links.append(attrs.get('href', ''))
        if tag in ('img', 'script', 'link'):
            url = attrs.get('src', attrs.get('href', ''))
            if url:
                self.assets.append(url)
        if 'data-fire-dot-value' in attrs:
            assert self.article == 'rules-source_fire_dot'
            key = attrs['data-fire-dot-value']
            assert key not in self.values, 'Duplicate Fire DoT numeric evidence: ' + key
            self.values[key] = float(attrs['data-value'])

    def handle_endtag(self, tag):
        if tag == 'article':
            self.article = None


def without_bonus(cast):
    result = deepcopy(cast)
    result['snapshot'].pop('fire_dot_multiplier', None)
    return result


def main():
    data = json.loads((REF / 'catalog.json').read_text())
    source = (REF / 'index.html').read_text()
    baseline = json.loads((QA / 'v052-reference-baseline.json').read_text())
    coverage = json.loads((REF / 'source-tree-coverage.json').read_text())
    fire = data['source_fire_dot']
    page = Page()
    page.feed(source)
    assert data['game_version'] == '0.53.0' and data['save_version'] == 32
    assert fire['minimum_save_version'] == 32
    assert fire['stat'] == 'fire_dot_multiplier_add' and fire['snapshot_field'] == 'fire_dot_multiplier'
    assert set(fire['nodes']) == set(fire['new_complete_ordinary_nodes']) == set(EXPECTED)
    assert fire['new_mastery_effect_ids'] == [] and fire['new_images'] == []
    assert fire['newly_reachable_existing_node'] == '1550'
    assert fire['older_legal_allocations_gaining_effects'] == []
    assert fire['source_sha256'] == data['source_tree']['source_sha256'] == baseline['source_sha256']
    tree = data['source_tree']
    rendered = {}
    for node_id, fraction in EXPECTED.items():
        node = fire['nodes'][node_id]
        near(node['fraction'], fraction)
        assert node['execution'] == tree['nodes'][node_id]['execution']
        assert node['execution']['status'] == 'full' and node['legacy_execution']['status'] != 'full'
        assert node['source_lines'] == tree['nodes'][node_id]['stats']
        grants = [g for g in node['execution']['grants'] if g['stat'] == fire['stat']]
        assert len(grants) == 1 and grants[0]['mode'] == 'flat'
        near(grants[0]['value'], fraction)
        rendered['node-' + node_id] = fraction
        article = re.search(r'<article\b[^>]*id="source_passives-' + node_id + r'"[^>]*>.*?</article>', source, re.S).group()
        assert 'rules-source_fire_dot' in article and '完整效果已接入' in article
    assert len(fire['examples']) == 8
    combinations = set()
    for index, example in enumerate(fire['examples']):
        base, zero, after = example['base'], example['explicit_zero'], example['increased']
        combinations.add((tuple(example['source_nodes']), example['skill_id'], example['support_id']))
        fraction = sum(EXPECTED[n] for n in example['source_nodes'])
        near(example['fraction'], fraction)
        assert base == zero, 'No source and explicit zero must preserve full compiled structure'
        assert 'fire_dot_multiplier' not in base['snapshot'] and 'fire_dot_multiplier' not in base['burn_profile']
        near(after['snapshot']['fire_dot_multiplier'], fraction)
        near(after['burn_profile']['fire_dot_multiplier'], fraction)
        assert after['packets'] == base['packets'] and after['recipe'] == base['recipe']
        assert after['mana'] == base['mana'] and after['cooldown'] == base['cooldown']
        assert without_bonus({'snapshot': after['snapshot']}) == {'snapshot': base['snapshot']}
        expected_roles = {'parent', 'child'} if example['skill_id'] == 'tornado' else {'direct'}
        assert set(after['burn_profile']['roles']) == expected_roles
        normalized = without_bonus(after)
        normalized['burn_profile'].pop('fire_dot_multiplier')
        for role, value in after['burn_profile']['roles'].items():
            before = base['burn_profile']['roles'][role]
            near(value['fire_before_defense'], before['fire_before_defense'])
            near(value['dps'], before['dps'] * (1 + fraction))
            near(value['total'], value['dps'] * base['burn_profile']['duration'])
            normalized['burn_profile']['roles'][role] = deepcopy(before)
            prefix = f'example-{index}-{role}-'
            rendered.update({prefix+'fraction': fraction, prefix+'fire': value['fire_before_defense'],
                             prefix+'before-dps': before['dps'], prefix+'after-dps': value['dps'],
                             prefix+'total': value['total'], prefix+'duration': after['burn_profile']['duration']})
        assert normalized == base, 'Fire DoT must change only its optional fraction and scaled burn values'
        assert '已计入上方数值' in example['details']
        legacy_examples = data['burning' if example['support_id'] == 'ignite' else 'ember_proliferation']['examples']
        assert base['burn_profile'] == legacy_examples[example['skill_id']]['profile']
    assert combinations == {(nodes, skill, support) for nodes in [('4713',), ('4713', '5916')]
                            for skill in ('meteor', 'tornado') for support in ('ignite', 'ember_proliferation')}
    assert len(fire['class_paths']) == len(coverage['class_reachability']) == 7
    routes = {r['class_id']: r for r in coverage['class_reachability']}
    for entry in fire['class_paths']:
        assert entry['old_reachable_count'] == 676 and entry['new_reachable_count'] == 685
        assert entry['legal_current_routes'] and entry['legacy_routes_rejected']
        assert set(entry['paths_to_new_nodes']) == set(EXPECTED)
        route = routes[entry['class_id']]
        assert route['reachable_count_excluding_start'] == 685
        assert '1550' in route['reachable_node_ids_including_start']
        for node_id, path in entry['paths_to_new_nodes'].items():
            assert path[0] == route['start_node_id'] and path[-1] == node_id
            assert len(path) == len(set(path)) and len(path)-1 <= 123
            for a, b in zip(path, path[1:]):
                assert b in tree['nodes'][a]['neighbors']
                assert tree['nodes'][b]['execution']['status'] == 'full'
                assert b in route['reachable_node_ids_including_start']
    assert len(fire['legal_build_examples']) == 3
    for index, example in enumerate(fire['legal_build_examples']):
        fraction = sum(EXPECTED.get(n, 0) for n in example['allocated'])
        near(example['stats'][fire['stat']], fraction)
        assert example['points_spent'] == len(example['allocated'])-1
        assert example['required_level'] == max(1, example['points_spent']-4)
        profile = example['cast']['burn_profile']
        near(profile['fire_dot_multiplier'], fraction)
        near(profile['roles']['direct']['dps'], profile['roles']['direct']['fire_before_defense'] * profile['rate_fraction'] * (1+fraction))
        rendered.update({f'legal-{index}-fraction': fraction, f'legal-{index}-dps': profile['roles']['direct']['dps']})
    transfer = fire['transfer_example']
    src, dst, inherited = transfer['source'], transfer['recipient'], transfer['transfer']['burn']
    near(src['raw_dps'], dst['raw_dps'])
    near(src['raw_dps'], inherited['raw_dps'])
    near(src['raw_dps'], data['ember_proliferation']['examples']['meteor']['profile']['roles']['direct']['dps']*1.10)
    assert src['provenance']['ember_expiry'] == dst['provenance']['ember_expiry'] == 13
    assert dst['provenance']['ember_generation'] == 1
    near(inherited['duration'], 13-transfer['transferred_at'])
    rendered.update({'transfer-fraction': .10, 'transfer-source-dps': src['raw_dps'],
                     'transfer-recipient-dps': dst['raw_dps'], 'transfer-started-at': 10,
                     'transfer-at': 11.75, 'transfer-expiry': 13, 'transfer-duration': 1.25})
    consumers = fire['unchanged_consumers']
    assert without_bonus(consumers['shock_after']) == consumers['shock_before']
    assert 'burn_profile' not in consumers['shock_after']
    near(consumers['enemy_burn']['raw_dps'], 7/3)
    assert consumers['enemy_burn']['duration'] == 3
    migration = fire['migration_example']
    assert (migration['from_version'], migration['to_version']) == (31, 32)
    assert migration['changed_fields'] == ['version'] and migration['talents_preserved']
    assert migration['items_before'] == migration['items_after']
    for key, expected_hash in baseline['structural_sha256'].items():
        value = deepcopy(data[key])
        if key == 'configurations':
            # Canonical stats exposes the new zero stat; frozen no-source casts above retain exact shape.
            assert value['fresh']['stats'].pop('fire_dot_multiplier_add') == 0
        if key == 'monster_attacks':
            # Player defense examples also expose that seeded zero stat, without changing settlement.
            for attack in ('locked_circle_cold', 'locked_circle_lightning'):
                for case in ('armored', 'moving', 'standing'):
                    assert value[attack]['example']['cases'][case]['defense_stats'].pop('fire_dot_multiplier_add') == 0
        assert digest(value) == expected_hash, 'Unchanged catalog structure drifted: ' + key
    assert digest({k: v for k, v in data['burning'].items() if k != 'source_words'}) == baseline['burning_without_source_words']
    shape = {k: {f: deepcopy(v) for f, v in n.items() if f != 'execution'} for k, n in tree['nodes'].items()}
    partial_entrances = []
    for node_id, node in shape.items():
        for choice in node['mastery_choices']:
            if choice['effect'] != 36313:
                continue
            partial_entrances.append(node_id)
            execution = choice['execution']
            assert execution == {'grants': [{'mode': 'flat', 'stat': fire['stat'], 'value': .12}],
                                 'status': 'partial', 'supported': ['+12% to Fire Damage over Time Multiplier'],
                                 'unsupported': ['50% increased Ignite Duration on you']}
            choice['execution'] = {'grants': [], 'status': 'unsupported', 'supported': [], 'unsupported': choice['stats']}
    assert set(partial_entrances) == {'11505', '19749', '34927', '37911', '38320', '40271', '48267', '63268'}
    assert digest(shape) == baseline['source_node_shape']
    other_execution = {k: deepcopy(n['execution']) for k, n in tree['nodes'].items() if k not in EXPECTED}
    excluded = tree['nodes']['12738']
    assert excluded['partition'] == 'Elementalist' and not excluded['standard_graph']
    assert excluded['execution'] == {'grants': [{'mode': 'flat', 'stat': fire['stat'], 'value': .04},
                                               {'mode': 'increased', 'stat': 'elemental_increased', 'value': .1}],
                                    'status': 'full', 'supported': excluded['stats'], 'unsupported': []}
    assert all('12738' not in route['reachable_node_ids_including_start'] for route in routes.values())
    other_execution['12738'] = {'grants': [{'mode': 'increased', 'stat': 'elemental_increased', 'value': .1}],
                               'status': 'partial', 'supported': ['10% increased Elemental Damage'],
                               'unsupported': ['+4% to Fire Damage over Time Multiplier']}
    assert digest(other_execution) == baseline['unchanged_source_execution']
    assert digest(tree['edges']) == baseline['source_edges'] and tree['starts'] == baseline['source_starts']
    images = {p.relative_to(REF).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in REF.rglob('*.png')}
    assert images == baseline['image_sha256'], 'No images may be added, removed or changed'
    assert set(page.values) == set(rendered)
    for key, value in rendered.items():
        near(page.values[key], value)
    assert len(page.ids) == len(set(page.ids))
    assert 'rules-source_fire_dot' in page.ids
    assert all(url[1:] in page.ids for url in page.links if url.startswith('#'))
    assert all(not re.match(r'(https?:)?//', url) and (REF/url).is_file() for url in page.assets)
    article = re.search(r'<article\b[^>]*id="rules-source_fire_dot"[^>]*>.*?</article>', source, re.S).group()
    for field in ['formula', 'units', 'snapshot_rule', 'preview_rule', 'scope', 'transfer_rule',
                  'coverage_note', 'complete_gate', 'legacy_rule', 'example_scope']:
        assert fire[field] in article
    assert '<style>' + (REF/'reference.css').read_text() + '</style>' in source
    assert '<script>' + (REF/'reference.js').read_text() + '</script>' in source
    print('Fire DoT reference PASS: exact 8 nodes, 56 legal class paths, 8 compiler comparisons, 3 complete route builds')
    print('No-source/zero structures, once-only scaled DPS/total and Ember expiry, old consumers/catalog data and 67 image hashes preserved')
    print(f'Validated {len(rendered)} rendered values, all internal links, schema31→32 evidence and same-source graph coverage')


if __name__ == '__main__':
    main()

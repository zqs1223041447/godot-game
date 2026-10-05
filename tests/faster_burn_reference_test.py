#!/usr/bin/env python3
"""Focused schema33 reference: actual compiler, exact source gates and frozen v53 data."""
import hashlib
import json
import math
import re
from copy import deepcopy
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REF = ROOT / 'docs/reference'
QA = ROOT / 'docs/qa/v054-reference'
EXPECTED = {'11364': .05, '43684': .05, '59766': .15}
BLOCKED = {'48823': ('30% increased Damage Over Time with Bow Skills', .10, True),
           '19686': ('20% increased Damage with Ailments', .05, False)}


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                    separators=(',', ':')).encode()).hexdigest()


def near(actual, expected):
    assert math.isfinite(actual) and abs(actual-expected) <= max(1e-9, 1e-12*abs(expected)), (actual, expected)


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids, self.links, self.assets = [], [], []
        self.article, self.values = None, {}

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
        if 'data-faster-burn-value' in attrs:
            assert self.article == 'rules-source_faster_burn'
            key = attrs['data-faster-burn-value']
            assert key not in self.values, 'Duplicate rendered evidence: ' + key
            self.values[key] = float(attrs['data-value'])

    def handle_endtag(self, tag):
        if tag == 'article':
            self.article = None


def without_faster_snapshot(cast):
    result = deepcopy(cast)
    result['snapshot'].pop('burn_faster', None)
    return result


def main():
    data = json.loads((REF/'catalog.json').read_text())
    source = (REF/'index.html').read_text()
    baseline = json.loads((QA/'v053-reference-baseline.json').read_text())
    coverage = json.loads((REF/'source-tree-coverage.json').read_text())
    faster, tree = data['source_faster_burn'], data['source_tree']
    page = Page()
    page.feed(source)
    assert data['game_version'] == '0.54.0' and data['save_version'] == 33
    assert faster['minimum_save_version'] == 33
    assert faster['stat'] == 'damaging_ailments_faster' and faster['snapshot_field'] == 'burn_faster'
    assert set(faster['nodes']) == set(faster['new_complete_ordinary_nodes']) == set(EXPECTED)
    assert faster['new_mastery_effect_ids'] == faster['new_images'] == faster['newly_reachable_existing_nodes'] == []
    assert faster['older_legal_allocations_gaining_effects'] == [] and faster['mastery_occurrences'] == 0
    assert faster['source_sha256'] == tree['source_sha256'] == baseline['source_sha256']
    assert faster['source_version'] == tree['source_version'] == '3.29.1'
    rendered = {}
    for node_id, fraction in EXPECTED.items():
        node = faster['nodes'][node_id]
        near(node['fraction'], fraction)
        assert node['execution'] == tree['nodes'][node_id]['execution']
        assert node['execution']['status'] == 'full' and node['legacy_execution']['status'] != 'full'
        assert node['source_lines'] == tree['nodes'][node_id]['stats']
        assert node['name'] == tree['nodes'][node_id]['name']
        grants = [g for g in node['execution']['grants'] if g['stat'] == faster['stat']]
        assert len(grants) == 1 and grants[0]['mode'] == 'flat'
        near(grants[0]['value'], fraction)
        rendered['node-'+node_id] = fraction
        article = re.search(r'<article\b[^>]*id="source_passives-'+node_id+r'"[^>]*>.*?</article>', source, re.S).group()
        assert 'rules-source_faster_burn' in article and '完整效果已接入' in article
    matching = {node_id for node_id, node in tree['nodes'].items()
                if any(re.fullmatch(r'Damaging Ailments deal damage \d+% faster', line) for line in node['stats'])}
    assert matching == set(EXPECTED) | set(BLOCKED)
    assert not any(re.fullmatch(r'Damaging Ailments deal damage \d+% faster', line)
                   for node in tree['nodes'].values() for choice in node['mastery_choices'] for line in choice['stats'])
    assert set(faster['blocked_matching_nodes']) == set(BLOCKED)
    for node_id, (unsupported, fraction, standard) in BLOCKED.items():
        node = faster['blocked_matching_nodes'][node_id]
        assert node['execution'] == tree['nodes'][node_id]['execution']
        assert node['standard_graph'] == tree['nodes'][node_id]['standard_graph'] == standard
        assert node['execution']['status'] == 'partial' and node['execution']['unsupported'] == [unsupported]
        assert node['source_lines'] == tree['nodes'][node_id]['stats']
        grants = [g for g in node['execution']['grants'] if g['stat'] == faster['stat']]
        assert len(grants) == 1
        near(grants[0]['value'], fraction)
    assert len(faster['examples']) == 8
    combinations = set()
    for index, example in enumerate(faster['examples']):
        base, zero, after = example['base'], example['explicit_zero'], example['faster']
        multiplier, fraction = example['fire_dot_multiplier'], example['faster_fraction']
        combinations.add((multiplier, example['skill_id'], example['support_id']))
        near(fraction, sum(EXPECTED[n] for n in example['source_nodes']))
        assert set(example['source_nodes']) == set(EXPECTED)
        assert base == zero and example['zero_bytes_equal'], 'Absent and explicit zero F retain all compiled bytes'
        assert 'burn_faster' not in base['snapshot']
        assert 'burn_faster' not in base['burn_profile'] and 'base_duration' not in base['burn_profile']
        near(after['snapshot']['burn_faster'], fraction)
        near(after['burn_profile']['burn_faster'], fraction)
        near(after['burn_profile']['base_duration'], 3)
        near(after['burn_profile']['duration'], 3/(1+fraction))
        assert after['packets'] == base['packets'] and after['recipe'] == base['recipe']
        assert after['mana'] == base['mana'] and after['cooldown'] == base['cooldown']
        assert without_faster_snapshot({'snapshot': after['snapshot']}) == {'snapshot': base['snapshot']}
        near(after['snapshot'].get('fire_dot_multiplier', 0), multiplier)
        near(after['burn_profile'].get('fire_dot_multiplier', 0), multiplier)
        expected_roles = {'parent', 'child'} if example['skill_id'] == 'tornado' else {'direct'}
        assert set(after['burn_profile']['roles']) == expected_roles
        normalized = without_faster_snapshot(after)
        normalized['burn_profile'].pop('burn_faster')
        normalized['burn_profile'].pop('base_duration')
        normalized['burn_profile']['duration'] = base['burn_profile']['duration']
        for role, part in after['burn_profile']['roles'].items():
            before = base['burn_profile']['roles'][role]
            assert part['fire_before_defense'] == before['fire_before_defense']
            near(part['dps'], before['dps']*(1+fraction))
            near(part['total'], part['dps']*after['burn_profile']['duration'])
            near(part['total'], before['total'])
            normalized['burn_profile']['roles'][role] = deepcopy(before)
            prefix = f'example-{index}-{role}-'
            rendered.update({prefix+'m': multiplier, prefix+'f': fraction, prefix+'fire': part['fire_before_defense'],
                             prefix+'before-dps': before['dps'], prefix+'after-dps': part['dps'],
                             prefix+'before-duration': base['burn_profile']['duration'], prefix+'after-duration': after['burn_profile']['duration'],
                             prefix+'before-total': before['total'], prefix+'after-total': part['total']})
        assert normalized == base, 'Only faster fields and effective burn DPS/duration/total may change'
        assert '燃烧结算加快 25%' in example['details']
        if multiplier:
            old = next(e for e in baseline['old_fire_dot_compiler_examples'] if e['source_nodes'] == ['4713', '5916']
                       and e['skill_id'] == example['skill_id'] and e['support_id'] == example['support_id'])
            assert base == old['increased'], 'Nonzero existing Fire DoT with absent/zero F must retain published v53 structure'
        else:
            old = next(e for e in baseline['old_fire_dot_compiler_examples'] if e['skill_id'] == example['skill_id']
                       and e['support_id'] == example['support_id'])
            assert base == old['base']
    assert combinations == {(m, skill, support) for m in (0, .10) for skill in ('meteor', 'tornado')
                            for support in ('ignite', 'ember_proliferation')}
    assert len(faster['class_paths']) == len(coverage['class_reachability']) == 7
    routes = {r['class_id']: r for r in coverage['class_reachability']}
    old_routes = {r['class_id']: r for r in baseline['class_reachability']}
    for entry in faster['class_paths']:
        assert entry['old_reachable_count'] == 685 and entry['new_reachable_count'] == 688
        assert entry['legal_current_routes'] and entry['legacy_routes_rejected']
        assert set(entry['paths_to_new_nodes']) == set(EXPECTED)
        route = routes[entry['class_id']]
        current_ids = set(route['reachable_node_ids_including_start'])
        old_ids = set(old_routes[entry['class_id']]['reachable_node_ids_including_start'])
        assert route['reachable_count_excluding_start'] == 688
        assert current_ids-old_ids == set(EXPECTED) and old_ids-current_ids == set()
        assert not current_ids.intersection(BLOCKED)
        for node_id, path in entry['paths_to_new_nodes'].items():
            assert path[0] == route['start_node_id'] and path[-1] == node_id
            assert len(path) == len(set(path)) and len(path)-1 <= 123
            for a, b in zip(path, path[1:]):
                assert b in tree['nodes'][a]['neighbors'] and b in current_ids
                assert tree['nodes'][b]['execution']['status'] == 'full'
    assert len(faster['legal_build_examples']) == 1
    for index, example in enumerate(faster['legal_build_examples']):
        assert set(EXPECTED).issubset(example['allocated'])
        near(example['stats'][faster['stat']], .25)
        assert example['points_spent'] == len(example['allocated'])-1
        assert example['required_level'] == max(1, example['points_spent']-4)
        profile = example['cast']['burn_profile']
        near(profile['burn_faster'], .25)
        near(profile['duration'], 2.4)
        near(profile['roles']['direct']['dps'], profile['roles']['direct']['fire_before_defense'] * profile['rate_fraction']
             * (1+profile.get('fire_dot_multiplier', 0)) * 1.25)
        rendered.update({f'legal-{index}-f': .25, f'legal-{index}-dps': profile['roles']['direct']['dps'],
                         f'legal-{index}-duration': profile['duration'], f'legal-{index}-total': profile['roles']['direct']['total']})
    transfer = faster['transfer_example']
    src, dst, inherited = transfer['source'], transfer['recipient'], transfer['transfer']['burn']
    near(src['raw_dps'], dst['raw_dps'])
    near(src['raw_dps'], inherited['raw_dps'])
    old_profile = baseline['old_burn_examples']['ember_proliferation']['meteor']['profile']
    near(src['raw_dps'], old_profile['roles']['direct']['dps']*1.10*1.25)
    near(src['provenance']['ember_expiry'], 12.4)
    assert src['provenance']['ember_expiry'] == dst['provenance']['ember_expiry']
    assert dst['provenance']['ember_generation'] == 1 and transfer['at_expiry']['burn'] == {}
    near(inherited['duration'], 12.4-transfer['transferred_at'])
    near(dst['remaining'], inherited['duration'])
    rendered.update({'transfer-m': .10, 'transfer-f': .25, 'transfer-source-dps': src['raw_dps'],
                     'transfer-recipient-dps': dst['raw_dps'], 'transfer-started-at': 10,
                     'transfer-at': 11.75, 'transfer-expiry': 12.4, 'transfer-duration': .65})
    consumers = faster['unchanged_consumers']
    assert without_faster_snapshot(consumers['shock_after']) == consumers['shock_before']
    assert 'burn_profile' not in consumers['shock_after']
    near(consumers['enemy_burn']['raw_dps'], 7/3)
    assert consumers['enemy_burn']['duration'] == 3
    migration = faster['migration_example']
    assert (migration['from_version'], migration['to_version']) == (32, 33)
    assert migration['changed_fields'] == ['version'] and migration['talents_preserved']
    assert migration['items_before'] == migration['items_after']
    normalized = deepcopy(data)
    for path in baseline['version_paths']:
        value = normalized
        for component in path[:-1]:
            value = value[component]
        assert value[path[-1]] == 33, path
        value[path[-1]] = 32
    zero_stat_paths = []
    def strip_new_zero(value, path):
        if isinstance(value, dict):
            if faster['stat'] in value:
                assert value.pop(faster['stat']) == 0, path
                zero_stat_paths.append(path+[faster['stat']])
            for key, child in value.items():
                strip_new_zero(child, path+[key])
        elif isinstance(value, list):
            for index, child in enumerate(value):
                strip_new_zero(child, path+[index])
    for key, expected_hash in baseline['structural_sha256'].items():
        value = normalized[key]
        strip_new_zero(value, [key])
        if key in baseline['excluded_text_fields']:
            value = {field: v for field, v in value.items() if field not in baseline['excluded_text_fields'][key]}
        assert digest(value) == expected_hash, 'Unexpected old catalog structure drift: '+key
    shape = {k: {f: v for f, v in n.items() if f != 'execution'} for k, n in tree['nodes'].items()}
    assert digest(shape) == baseline['source_node_shape'], 'Original English names/stats/masteries/geometry must remain exact'
    other_execution = {k: n['execution'] for k, n in tree['nodes'].items() if k not in set(EXPECTED) | set(BLOCKED)}
    assert digest(other_execution) == baseline['unchanged_source_execution']
    assert digest(tree['edges']) == baseline['source_edges'] and tree['starts'] == baseline['source_starts']
    images = {p.relative_to(REF).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in REF.rglob('*.png')}
    assert images == baseline['image_sha256']
    assert set(page.values) == set(rendered), (set(page.values)-set(rendered), set(rendered)-set(page.values))
    for key, value in rendered.items():
        near(page.values[key], value)
    assert len(page.ids) == len(set(page.ids)) and 'rules-source_faster_burn' in page.ids
    assert all(url[1:] in page.ids for url in page.links if url.startswith('#'))
    assert all(not re.match(r'(https?:)?//', url) and (REF/url).is_file() for url in page.assets)
    article = re.search(r'<article\b[^>]*id="rules-source_faster_burn"[^>]*>.*?</article>', source, re.S).group()
    for field in ['formula','units','total_rule','snapshot_rule','preview_rule','zero_rule','scope','transfer_rule',
                  'coverage_note','complete_gate','legacy_rule','example_scope']:
        assert faster[field] in article
    assert '更快异常仍未实现' not in source
    assert '<style>'+(REF/'reference.css').read_text()+'</style>' in source
    assert '<script>'+(REF/'reference.js').read_text()+'</script>' in source
    print('Faster burn reference PASS: exact 3 nodes, 21 legal class paths, 8 real compiler comparisons, complete 3-node legal branch')
    print('M=0.10/F=0.25, effective DPS/duration/total, compressed Ember expiry, source gates, no extra reachability and schema32→33 verified')
    print(f'Published v53 absent/zero-F structures, 58 old catalog sections, {len(images)} image hashes and {len(rendered)} rendered values preserved/verified')
    print('Intentional derived-stat zero fields: '+json.dumps(zero_stat_paths, ensure_ascii=False))


if __name__ == '__main__':
    main()

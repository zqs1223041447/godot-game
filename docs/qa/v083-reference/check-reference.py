#!/usr/bin/env python3
"""Check the new-map fragment, real Main provenance, diagram and baseline bytes."""
import hashlib
import importlib.util
import json
import math
import re
import subprocess
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
QA = Path(__file__).resolve().parent
REF = ROOT / 'docs/reference'
BASE = 'f18cf07'
spec = importlib.util.spec_from_file_location('merge_fragment', QA/'merge-fragment.py')
merge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(merge)

def sha(data): return hashlib.sha256(data).hexdigest()
def baseline(path): return subprocess.check_output(['git', 'show', BASE+':'+path], cwd=ROOT)
def near(actual, expected): assert math.isfinite(actual) and abs(actual-expected) < 1e-12, (actual, expected)

def numeric_agreement(actual, expected, differences, path=''):
    """Only reserialized Main floating scalars may differ by <= 1e-12."""
    if actual == expected: return
    if isinstance(actual, dict) and isinstance(expected, dict):
        assert actual.keys() == expected.keys(), path
        for key in actual: numeric_agreement(actual[key], expected[key], differences, path+'/'+key)
    elif isinstance(actual, list) and isinstance(expected, list):
        assert len(actual) == len(expected), path
        for index, (left, right) in enumerate(zip(actual, expected)):
            numeric_agreement(left, right, differences, path+'/'+str(index))
    else:
        assert isinstance(actual, float) and isinstance(expected, float), (path, actual, expected)
        near(actual, expected)
        differences.append({'path':path,'exported':actual,'main_original':expected,'absolute_difference':abs(actual-expected)})

def vectors(value):
    if isinstance(value, dict): return {key: vectors(item) for key, item in value.items()}
    if isinstance(value, list): return [vectors(item) for item in value]
    if isinstance(value, str) and re.fullmatch(r'\(-?[0-9.]+, -?[0-9.]+\)', value):
        return [float(part) for part in value[1:-1].split(', ')]
    return value

class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids, self.links, self.assets, self.values = [], [], [], []
        self.walls, self.roots, self.triggers, self.markers = {}, {}, {}, {}
        self.active = None
        self.viewbox = None
    def handle_starttag(self, tag, pairs):
        attrs = dict(pairs)
        if 'id' in attrs: self.ids.append(attrs['id'])
        if 'href' in attrs: self.links.append(attrs['href'])
        if 'src' in attrs: self.assets.append(attrs['src'])
        if 'data-ginkgo-path' in attrs:
            self.values.append([attrs['data-ginkgo-path'], float(attrs['data-value']), ''])
            self.active = len(self.values)-1
        if 'data-ginkgo-layout' in attrs: self.viewbox = list(map(float, attrs['viewbox'].split()))
        for name, target in [('wall', self.walls), ('root', self.roots), ('trigger', self.triggers)]:
            if 'data-ginkgo-'+name in attrs: target[attrs['data-ginkgo-'+name]] = attrs
        for name in ['entry', 'boss']:
            if 'data-ginkgo-'+name in attrs: self.markers[name] = attrs
    def handle_data(self, text):
        if self.active is not None: self.values[self.active][2] += text
    def handle_endtag(self, tag):
        if tag == 'strong': self.active = None

def main():
    raw = (REF/'catalog.json').read_text()
    oldraw = baseline('docs/reference/catalog.json').decode()
    data, old = json.loads(raw), json.loads(oldraw)
    fragment = json.loads((QA/'ginkgo-fragment.json').read_text())
    proof = json.loads((QA/'catalog-format-preservation.json').read_text())
    ginkgo = data['ginkgo_arcade']
    assert data == {**old, **fragment} and set(data)-set(old) == {'ginkgo_arcade'}
    assert data['game_version'] == '0.83.0' and data['save_version'] == ginkgo['save_version'] == 50
    assert data['source_tree']['source_policy'] == ginkgo['source_policy'] == 49
    assert ginkgo['equipment_vocabulary'] == 46
    assert proof['splice_count'] == 3 and proof['historical_raw_section_count'] == len(old)-2
    before, after = merge.spans(oldraw), merge.spans(raw)
    for key in proof['historical_raw_sections_preserved']:
        _, a, b = before[key]
        _, c, d = after[key]
        assert oldraw[a:b] == raw[c:d], key
    assert ginkgo['definition']['id'] == 'ginkgo_arcade'
    assert ginkgo['definition']['boss_attack_id'] == 'ginkgo_shelter_slam'
    assert ginkgo['test_profile']['wave'] == 6 and not ginkgo['test_profile'].get('normal_map')
    assert len(ginkgo['tiers']) == 3
    for index, row in enumerate(ginkgo['tiers']):
        profile, legal = row['base'], row['legal_precondition']
        assert profile['journey_tier'] == index+1 and profile['wave'] == [3, 6, 10][index]
        assert profile['fee'] == [0, 4, 8][index] and profile['completion_reward'] == [4, 8, 12][index]
        assert legal['whole_model_valid'] and legal['helper_profile_matches'] and legal['best_completed'] == index
        assert legal['schema'] == 50 and profile['ordinary_target'] == 36
        assert row['maximum_bonus_example']['completion_reward'] - profile['completion_reward'] == [2, 4, 4][index]
        assert row['eligible_special_ids'] == ([] if index == 0 else ['elemental_aegis', 'frost_patrol', 'storm_patrol'])
    for name in ['fixture_helper', 'native49_fixture', 'actual_main_report', 'freeze_source', 'freeze_cast']:
        source = ginkgo[name]
        assert sha((ROOT/source['path']).read_bytes()) == source['sha256'], name
    report = json.loads((ROOT/ginkgo['actual_main_report']['path']).read_text())
    assert report['failures'] == 0 and report['checks'] == ginkgo['actual_main_checks'] > 0
    assert len(ginkgo['actual_main_examples']) == len(report['runs']) == 2
    float_roundtrips=[]
    for entry, run in zip(ginkgo['actual_main_examples'], report['runs']):
        assert entry['tier'] == run['tier'] and entry['whole_model_valid']
        assert entry['whole_profile_matches_main'] and entry['whole_roster_matches_main']
        assert entry['profile'] == run['profile'] and vectors(entry['roster']) == vectors(run['roster'])
        assert entry['roster']['seed'] == run['roster']['seed'], 'Exact 64-bit Main seed'
        assert entry['roots_rewarded'] == 37 and entry['coexisting_roots'] == 36 and entry['boss_children'] == 4
        assert entry['pending'] == run['pending'] and entry['claim'] == run['claim']
        attack = report['attacks'][str(entry['tier'])]
        numeric_agreement(entry['attack_profile'],attack['attack']['profile'],float_roundtrips,str(entry['tier'])+'/attack_profile')
        numeric_agreement(entry['policy']['profile'],attack['attack']['profile'],float_roundtrips,str(entry['tier'])+'/policy_profile')
        assert entry['source_attack_speed'] == attack['boss']['attack_speed']
        numeric_agreement(entry['packet'],attack['attack']['packet'],float_roundtrips,str(entry['tier'])+'/packet')
        assert entry['locked_center'] == vectors(attack['attack']['center'])
        assert sha((ROOT/entry['model']['path']).read_bytes()) == entry['model']['sha256']
        model = json.loads((ROOT/entry['model']['path']).read_text())
        assert model['version'] == 50 and model['journey']['best_tiers']['ginkgo_arcade'] == entry['tier']
        for camp in entry['roster']['camps']:
            assert len(camp['entries']) == 12 and all(row['template_id'] != 'mist_skitter' for row in camp['entries'])
    boss = ginkgo['boss_definition']
    assert boss['name'] == '回廊震击' and boss['target_rule'] == 'self_at_start'
    assert boss['profile'] == {'radius': 240, 'windup_seconds': 1.4, 'recovery_seconds': 1.9, 'damage_multiplier': 1.2}
    assert boss['trigger_distance'] == 240 and 'pulse_count' not in boss
    near(ginkgo['actual_freeze_seconds'], .24)
    geometry = ginkgo['geometry']
    assert geometry['obstacle_style'] == 'ginkgo_planters' and len(geometry['walls']) == 3
    marks = geometry['landmarks']
    assert len(marks['camps']) == 3 and all(camp['root_count'] == len(camp['positions']) == 12 for camp in marks['camps'])
    html = (REF/'index.html').read_text()
    oldhtml = baseline('docs/reference/index.html').decode()
    page, oldpage = Page(), Page()
    page.feed(html)
    oldpage.feed(oldhtml)
    assert len(page.ids) == len(set(page.ids))
    assert set(page.ids)-set(oldpage.ids) == {'maps-ginkgo_arcade'} and set(oldpage.ids) <= set(page.ids)
    for path, actual, label in page.values:
        expected = ginkgo
        for field in path.split('/'): expected = expected[int(field)] if isinstance(expected, list) else expected[field]
        assert actual == expected and label == format(expected, 'g'), (path, actual, label)
    assert len(page.values) >= 30
    assert page.viewbox == geometry['bounds']['position'] + geometry['bounds']['size']
    assert len(page.walls) == 3 and len(page.roots) == 36 and len(page.triggers) == 4
    for index, wall in enumerate(geometry['walls']):
        attrs = page.walls[str(index)]
        assert [float(attrs[key]) for key in ['x', 'y', 'width', 'height']] == wall['position'] + wall['size']
    for index, camp in enumerate(marks['camps']):
        attrs = page.triggers[str(index)]
        assert [float(attrs[key]) for key in ['cx', 'cy', 'r']] == camp['trigger_center'] + [camp['trigger_radius']]
        for ordinal, position in enumerate(camp['positions']):
            attrs = page.roots[f'{index}-{ordinal}']
            assert [float(attrs[key]) for key in ['cx', 'cy']] == position
    for name, point in [('entry', marks['entry']), ('boss', marks['boss']['center'])]:
        assert [float(page.markers[name][key]) for key in ['cx', 'cy']] == point
    assert [float(page.triggers['boss'][key]) for key in ['cx', 'cy', 'r']] == marks['boss']['trigger_center'] + [marks['boss']['trigger_radius']]
    for link in page.links:
        if link.startswith('#'): assert link[1:] in page.ids, link
        elif link and not link.startswith(('http:', 'https:', 'mailto:')): assert (REF/link.split('#')[0]).is_file(), link
    for asset in page.assets: assert not asset.startswith(('http:', 'https:')) and (REF/asset).is_file(), asset
    def cards(text): return {re.search(r'id="([^"]+)"',match).group(1): match for match in re.findall(r'<article\b.*?</article>', text, re.S)}
    oldcards, newcards = cards(oldhtml), cards(html)
    preserved, labels, map_links = [], [], []
    substitutions = [('运行版本 0.82.0', '运行版本 0.83.0'), ('当前存档结构 49', '当前存档结构 50'),
                     ('当前存档 49；当前源执行政策 49', '当前存档 50；当前源执行政策 49'),
                     ('当前存档49、源政策49', '当前存档50、源政策49')]
    for key, original in oldcards.items():
        expected = original
        applied = []
        for before_label, after_label in substitutions:
            if before_label in expected:
                expected = expected.replace(before_label, after_label)
                applied.append([before_label, after_label])
        if key.startswith('map_specials-'):
            assert expected.endswith('</div></article>')
            expected=expected[:-len('</div></article>')]+' · <a href="#maps-ginkgo_arcade">银杏回廊</a></div></article>'
            map_links.append({'card':key,'change':'Append the new eligible map link; all previous bytes retained'})
        if key=='town_services-map_device':
            paragraph='<p>当前可用四张地图：'+' · '.join('<a href="#maps-'+entry['id']+'">'+entry['name']+'</a>' for entry in old['town_maps']['options']['maps']+[ginkgo['definition']])+'。正式地图各有I/II/III独立成长；独立测试地图免费，正式入场沿分档费用。</p>'
            expected=expected.replace('<p>重进测试档',paragraph+'<p>重进测试档')
            map_links.append({'card':key,'change':'Add current four-map navigation and formal/test cost clarification; retain prior text'})
        assert expected == newcards[key], key
        if expected == original: preserved.append(key)
        elif applied: labels.append({'card': key, 'labels': applied})
    for name in ['old_garden', 'broken_ruins', 'sunwell_terrace']:
        assert oldcards['maps-'+name] == newcards['maps-'+name]
    payload=json.loads(re.search(r'<script id="reference-data" type="application/json">(.*?)</script>',html,re.S).group(1))
    map_records=[row for row in payload['records'] if row['cat']=='maps']
    assert [row['id'] for row in map_records]==['maps-old_garden','maps-broken_ruins','maps-sunwell_terrace','maps-ginkgo_arcade']
    assert all(term in map_records[-1]['search'] for term in ['银杏回廊','ginkgo_arcade','回廊震击'])
    assert re.search(r'id="category-maps"[^>]*><span>有限地图</span><span>4</span>',html)
    assert '当前可用四张地图' in newcards['town_services-map_device']
    assert all('#maps-ginkgo_arcade' in newcards['map_specials-'+key] for key in ['elemental_aegis','frost_patrol','storm_patrol'])
    protected = {}
    tree = subprocess.check_output(['git', 'ls-tree', '-r', BASE, 'assets', 'data', 'docs/reference'], cwd=ROOT, text=True)
    pngs = []
    for line in tree.splitlines():
        info, path = line.split('\t', 1)
        if path.startswith('data/') or path.endswith('.png') or path in ['docs/reference/source-tree-coverage.json', 'docs/reference/reference.css', 'docs/reference/reference.js', 'docs/reference/art/manifest.json']:
            payload = (ROOT/path).read_bytes()
            assert hashlib.sha1(b'blob '+str(len(payload)).encode()+b'\0'+payload).hexdigest() == info.split()[2], path
            protected[path] = sha(payload)
            if path.endswith('.png'): pngs.append(path)
    actual_pngs = {str(path.relative_to(ROOT)) for folder in [ROOT/'assets', ROOT/'data', REF] for path in folder.rglob('*.png')}
    assert actual_pngs == set(pngs), 'No new image files'
    result = {'passed': True, 'baseline_commit': BASE, 'new_anchor': 'maps-ginkgo_arcade',
              'legal_helper_tiers': 3, 'actual_main_profiles_and_rosters': 2, 'main_report_checks': report['checks'],
              'exact_64_bit_main_seeds': [run['roster']['seed'] for run in report['runs']],
              'new_main_float_roundtrips_within_1e_12':float_roundtrips,
              'authoritative_html_values': len(page.values), 'authoritative_diagram_walls': 3,
              'authoritative_diagram_root_markers': 36, 'authoritative_diagram_triggers': 4,
              'historical_raw_sections_preserved': len(proof['historical_raw_sections_preserved']),
              'old_cards_byte_preserved': len(preserved), 'version_label_only_cards': labels,
              'new_map_link_only_cards':map_links,'map_category_count':len(map_records),'map_category_order_and_search_valid':True,
              'old_map_cards_byte_preserved': 3, 'old_anchors_preserved': len(oldpage.ids),
              'protected_files': len(protected), 'preserved_pngs': len(pngs), 'source_coverage_byte_preserved': True,
              'all_links_and_assets_valid': True, 'catalog_sha256': sha(raw.encode()), 'html_sha256': sha(html.encode()),
              'coverage_sha256': sha((REF/'source-tree-coverage.json').read_bytes()),
              'scope': 'One bounded new-map runtime fragment. Existing lawful fixture helper and accepted Main evidence reused. No full catalog/coverage export, new art, combat replay, 600s test, native F8 visual review, package or release.'}
    with (QA/'preservation.json').open('x') as handle:
        json.dump(result, handle, ensure_ascii=False, indent=2)
        handle.write('\n')
    print(json.dumps(result, ensure_ascii=False, indent=2))

if __name__ == '__main__': main()

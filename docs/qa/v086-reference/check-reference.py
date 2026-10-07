#!/usr/bin/env python3
"""One bounded static/source/provenance check; no Godot or gameplay rerun."""
import hashlib
import html as html_module
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
BASE = 'eb487876'
spec = importlib.util.spec_from_file_location('merge_fragment', QA/'merge-fragment.py')
merge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(merge)


def sha(raw): return hashlib.sha256(raw).hexdigest()
def baseline(path): return subprocess.check_output(['git', 'show', BASE+':'+path], cwd=ROOT)


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids, self.links, self.assets = [], [], []
        self.layout, self.walls, self.spawns, self.signs, self.entry = None, {}, {}, {}, None
    def handle_starttag(self, tag, pairs):
        attrs = dict(pairs)
        if 'id' in attrs: self.ids.append(attrs['id'])
        if 'href' in attrs: self.links.append(attrs['href'])
        if 'src' in attrs: self.assets.append(attrs['src'])
        if 'data-exploration-layout' in attrs: self.layout = attrs
        if 'data-exploration-wall' in attrs: self.walls[int(attrs['data-exploration-wall'])] = attrs
        if 'data-exploration-spawn' in attrs: self.spawns[attrs['data-exploration-spawn']] = attrs
        if 'data-exploration-sign' in attrs: self.signs[attrs['data-exploration-sign']] = attrs
        if 'data-exploration-entry' in attrs: self.entry = attrs


def check_geometry(map_id, entry, card, entry_clearance):
    page = Page(); page.feed(card)
    shape = entry['geometry']; bounds = shape['bounds']; plan = entry['plan_example']
    assert bounds['size'] == [3600, 2400]
    assert list(map(float, page.layout['viewbox'].split())) == bounds['position'] + bounds['size']
    assert page.layout['data-exploration-layout'] == map_id
    assert len(page.walls) == len(shape['walls'])
    for index, wall in enumerate(shape['walls']):
        assert [float(page.walls[index][key]) for key in ['x', 'y', 'width', 'height']] == wall['position'] + wall['size']
    assert len(page.spawns) == plan['total'] == entry['ordinary_target'] + 1
    assert plan['mechanism_config'] == {} and plan['optional_encounters'] == []
    seen = set()
    for root, record in zip(plan['roots'], plan['spawn_records'], strict=True):
        assert root['actor_id'] == root['root_id'] == record['actor_id'] == record['root_id']
        assert root['generation'] == 0 and root['reward_eligible'] is True and root['awake'] is False
        assert root['position'] == record['position'] and root['spawn_key'] == record['spawn_key']
        assert math.dist(root['position'], shape['landmarks']['entry']) >= entry_clearance
        assert root['actor_id'] not in seen; seen.add(root['actor_id'])
        assert record['encounter_id'] == '' and record['reward_route'] == 'standard'
        dot = page.spawns[record['spawn_key']]
        assert [float(dot['cx']), float(dot['cy'])] == record['position']
        assert dot['data-template'] == record['template_id']
    assert [float(page.entry['cx']), float(page.entry['cy'])] == shape['landmarks']['entry']
    assert set(page.signs) == {'camp_west', 'camp_north', 'camp_east', 'boss'}
    for landmark in shape['landmarks']['camps'] + [{**shape['landmarks']['boss'], 'id': 'boss'}]:
        x, y = landmark['sign_position']
        assert page.signs[landmark['id']]['d'] == f'M{x} {y-20}v40M{x-20} {y-20}h40v22h-40z'
    assert 'data-ginkgo-trigger' not in card and 'data-ginkgo-layout' not in card
    for stale in ['靠近木牌64', '全部普通根怪死亡后开启', '击败全部据点根怪后激活', '进入木牌 ', '整组等待']:
        assert stale not in card, (map_id, stale)
    assert '醒后持续追击' in card and '待出生后代队列' in card
    assert [row['profile']['fee'] for row in entry['tiers']] == [0, 4, 8]
    assert [row['profile']['completion_reward'] for row in entry['tiers']] == [4, 8, 12]
    for row in entry['tiers']:
        assert row['maximum_modifier_bonus'] == (4 if row['eligible_special_ids'] else 2)
    return {'walls': len(page.walls), 'real_initial_actors': len(page.spawns), 'signs': len(page.signs), 'entry_checked': True}


def main():
    raw = (REF/'catalog.json').read_text(); oldraw = baseline('docs/reference/catalog.json').decode()
    data = json.loads(raw); old = json.loads(oldraw)
    fragment = json.loads((QA/'exploration-fragment.json').read_text())
    assert data == {**old, **fragment} and set(data)-set(old) == {'exploration_maps'}
    exploration = data['exploration_maps']
    assert data['game_version'] == '0.86.0'
    assert data['save_version'] == exploration['save_version'] == 50
    assert data['source_tree']['source_policy'] == exploration['source_policy'] == 49
    assert exploration['equipment_vocabulary'] == 46 and exploration['aggro_radius'] == 450
    before, after = merge.spans(oldraw), merge.spans(raw)
    preserved_sections = []
    for key, (_, start, end) in before.items():
        if key == 'game_version': continue
        _, a, b = after[key]
        assert oldraw[start:end] == raw[a:b], key
        preserved_sections.append(key)
    html = (REF/'index.html').read_text(); oldhtml = baseline('docs/reference/index.html').decode()
    current_cards = {key: value for value, key in re.findall(r'(<article\b[^>]*\bid="([^"]+)"[^>]*>.*?</article>)', html, re.S)}
    old_cards = {key: value for value, key in re.findall(r'(<article\b[^>]*\bid="([^"]+)"[^>]*>.*?</article>)', oldhtml, re.S)}
    intended = {'maps-'+key for key in exploration['maps']} | {'town_services-map_device'}
    assert set(current_cards) - set(old_cards) == {'rules-exploration_maps'}
    assert set(old_cards) <= set(current_cards)
    stale_patterns = [r'靠近.{0,20}(?:木牌|据点).{0,15}(?:激活|出生)',
                      r'(?:全部|击败|清完|清理).{0,15}根怪.{0,20}(?:后|再).{0,12}(?:首领入口|激活首领|首领出现)',
                      r'进入木牌.{0,30}(?:出现|出生)']
    for key, card in current_cards.items():
        visible_text = html_module.unescape(re.sub(r'<[^>]*>', ' ', card))
        for pattern in stale_patterns:
            assert re.search(pattern, visible_text) is None, (key, pattern)
    identical, version_only = [], []
    for key, old_card in old_cards.items():
        current = current_cards[key]
        if key in intended:
            assert current != old_card
        elif current == old_card: identical.append(key)
        else:
            assert current == old_card.replace(old['game_version'], data['game_version']), key
            version_only.append(key)
    shape_checks = {key: check_geometry(key, entry, current_cards['maps-'+key], exploration['entry_clearance']) for key, entry in exploration['maps'].items()}
    assert len(shape_checks) == 4
    preserved_profiles = {(row['id'], row['journey_tier']): row for row in old['normal_journey']['tiers']}
    preserved_profiles.update({('ginkgo_arcade', row['base']['journey_tier']): row['base'] for row in old['ginkgo_arcade']['tiers']})
    for map_id, entry in exploration['maps'].items():
        for tier in entry['tiers']:
            assert tier['profile'] == preserved_profiles[(map_id, tier['profile']['journey_tier'])], (map_id, tier['profile']['journey_tier'])
    for path in ['scripts/world/map_catalog.gd', 'scripts/world/normal_map_catalog.gd', 'scripts/world/map_compiler.gd']:
        assert (ROOT/path).read_bytes() == baseline(path), path
    allpage = Page(); allpage.feed(html)
    oldpage = Page(); oldpage.feed(oldhtml)
    assert len(allpage.ids) == len(set(allpage.ids)) and set(oldpage.ids) <= set(allpage.ids)
    for link in allpage.links:
        if link.startswith('#'): assert link[1:] in allpage.ids, link
        elif not re.match(r'^[a-z]+:', link): assert (REF / link.split('#')[0]).resolve().exists(), link
    for asset in allpage.assets:
        if not re.match(r'^[a-z]+:', asset): assert (REF / asset).is_file(), asset
    paths = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', BASE, '--', 'docs/reference'], cwd=ROOT, text=True).splitlines()
    protected = []
    for path in paths:
        if path in ['docs/reference/catalog.json', 'docs/reference/index.html']: continue
        assert (ROOT/path).read_bytes() == baseline(path), path
        protected.append(path)
    assert {str(p.relative_to(ROOT)) for p in REF.rglob('*.png')} == {p for p in paths if p.endswith('.png')}
    provenance = {}
    for key in ['plan_test', 'plan_test_inputs', 'actual_main_report', 'main_acceptance', 'focused_input_report']:
        source = exploration[key]
        assert sha((ROOT/source['path']).read_bytes()) == source['sha256']
        provenance[key] = source
    accepted = json.loads((ROOT/exploration['actual_main_report']['path']).read_text())
    assert accepted['checks'] == exploration['actual_main_checks'] == 245 and accepted['failures'] == exploration['actual_main_original_failures'] == 1
    acceptance = json.loads((ROOT/exploration['main_acceptance']['path']).read_text())
    focused = json.loads((ROOT/exploration['focused_input_report']['path']).read_text())
    assert acceptance['ok'] and acceptance['main_core_flow_accepted'] and acceptance['full_run']['original_result_preserved']
    assert acceptance['full_run']['unresolved_product_failures'] == 0 and acceptance['unchanged_production_proof']['all_unchanged']
    assert focused['checks'] == exploration['focused_input_checks'] == 10 and focused['failures'] == 0
    for path, record in acceptance['unchanged_production_proof']['files'].items():
        assert sha((ROOT/path).read_bytes()) == record['first_run_sha256'] == record['current_sha256']
    for actual_entry in accepted['entries']:
        entry = exploration['maps'][actual_entry['map_id']]
        assert entry['actual_main_entry'] == {'entry': actual_entry['entry'], 'actor_ids': actual_entry['ids'], 'spawn_records': actual_entry['records']}
        planned_positions = {(record['source_group'], record['ordinal']): record['position'] for record in entry['plan_example']['spawn_records']}
        for record in actual_entry['records']:
            position = [float(value) for value in record['position'][1:-1].split(', ')]
            assert position == planned_positions[(record['source_group'], record['ordinal'])]

    plan_result = json.loads((ROOT/exploration['plan_test']['path']).read_text())
    assert plan_result['exit_code'] == 0 and plan_result['error_logged'] is False
    plan_inputs = json.loads((ROOT/exploration['plan_test_inputs']['path']).read_text())
    for path, digest in plan_inputs.items():
        if path == 'scripts/main.gd': continue  # The independent Plan test does not load Main.
        assert sha((ROOT/path).read_bytes()) == digest, path
    builder_spec = importlib.util.spec_from_file_location('build_reference', ROOT/'tools/build_reference.py')
    builder = importlib.util.module_from_spec(builder_spec); builder_spec.loader.exec_module(builder)
    assert builder.build(data, json.loads((REF/'art/manifest.json').read_text())) == html
    proof = {'baseline_commit': BASE, 'preserved_raw_top_level_count': len(preserved_sections),
             'preserved_raw_top_level_sections': preserved_sections, 'byte_identical_card_count': len(identical),
             'only_game_version_label_changed': version_only, 'replaced_current_cards': sorted(intended),
             'new_current_cards': ['rules-exploration_maps'], 'preserved_anchor_count': len(oldpage.ids),
             'layouts': shape_checks, 'protected_file_count': len(protected),
             'protected_png_count': sum(path.endswith('.png') for path in protected),
             'coverage_and_png_bytes_preserved': True, 'no_new_pngs': True,
             'all_current_cards_scanned_for_obsolete_spawn_or_boss_gate_text': True,
             'remaining_group_mentions_reviewed': ['monsters-mist_skitter: unchanged per-group species budget', 'rules-source_monster_movement: unchanged current roster policy entry'],
             'main_and_plan_provenance': provenance, 'actual_main_checks': accepted['checks'], 'original_main_failures_preserved': 1,
             'focused_input_checks': 10, 'combined_main_acceptance': True,
             'build_matches': True, 'all_local_links_resolve': True, 'all_12_persistent_tier_profiles_equal_historical_export': True,
             'scope': 'Static/source/provenance only. No gameplay rerun, full export, native F8 visual or release validation.'}
    with (QA/'preservation.json').open('x') as handle: json.dump(proof, handle, ensure_ascii=False, indent=2); handle.write('\n')
    print(json.dumps({key: value for key, value in proof.items() if key != 'preserved_raw_top_level_sections'}, ensure_ascii=False, indent=2))


if __name__ == '__main__': main()

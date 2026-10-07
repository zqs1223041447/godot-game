#!/usr/bin/env python3
"""Focused output/provenance/preservation check; no Godot or gameplay run."""
import hashlib
import importlib.util
import json
import re
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
QA = Path(__file__).resolve().parent
REF = ROOT / 'docs/reference'


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


merge = module('merge_fragment', QA / 'merge-fragment.py')
builder = module('build_reference', ROOT / 'tools/build_reference.py')


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids, self.links, self.assets = [], [], []
        self.layout, self.entry = None, None
        self.walls, self.spawns, self.signs, self.routes = {}, {}, {}, {}

    def handle_starttag(self, tag, pairs):
        attrs = dict(pairs)
        if 'id' in attrs: self.ids.append(attrs['id'])
        if 'href' in attrs: self.links.append(attrs['href'])
        if 'src' in attrs: self.assets.append(attrs['src'])
        if 'data-exploration-layout' in attrs: self.layout = attrs
        if 'data-exploration-entry' in attrs: self.entry = attrs
        for kind in ['wall', 'spawn', 'sign', 'route']:
            key = 'data-exploration-' + kind
            if key in attrs: getattr(self, {'wall': 'walls', 'spawn': 'spawns', 'sign': 'signs', 'route': 'routes'}[kind])[attrs[key]] = attrs


def cards(html):
    return {key: value for value, key in re.findall(r'(<article\b[^>]*\bid="([^"]+)"[^>]*>.*?</article>)', html, re.S)}


def main():
    frozen = json.loads((QA / 'frozen-inputs.json').read_text())
    for path, digest in frozen['production'].items(): assert sha(ROOT / path) == digest, path
    for path, evidence in frozen['protected_reference'].items():
        assert {'sha256': sha(ROOT / path), 'mtime_ns': (ROOT / path).stat().st_mtime_ns} == evidence, path
    protected_now = {str(path.relative_to(ROOT)) for path in REF.rglob('*') if path.is_file() and path.name not in ['catalog.json', 'index.html']}
    assert protected_now == set(frozen['protected_reference'])
    raw = (REF / 'catalog.json').read_text()
    oldraw = merge.baseline('docs/reference/catalog.json').decode()
    data, old = json.loads(raw), json.loads(oldraw)
    assert set(data) == set(old)
    for key, value in merge.tokens(oldraw).items():
        if key != 'exploration_maps': assert merge.tokens(raw)[key] == value, key
    assert data['game_version'] == '0.87.0' and data['save_version'] == 50
    current = data['exploration_maps']
    assert current['save_version'] == 50 and current['source_policy'] == 49 and current['equipment_vocabulary'] == 46
    assert current['route_distribution'] == {'version': 'route_outposts_v1', 'outpost_count': 6, 'route_width': 72.0, 'source_group_count': 3}
    fragment = json.loads((QA / 'exploration-fragment.json').read_text())
    old_maps = merge.tokens(merge.tokens(merge.tokens(oldraw)['exploration_maps'])['maps'])
    new_maps = merge.tokens(merge.tokens(merge.tokens(raw)['exploration_maps'])['maps'])
    for map_id in old_maps:
        for key, value in merge.tokens(old_maps[map_id]).items():
            if key not in ['geometry', 'description', 'plan_example', 'actual_main_entry']:
                assert merge.tokens(new_maps[map_id])[key] == value, (map_id, key)
        for key, value in fragment['maps'][map_id].items(): assert current['maps'][map_id][key] == value, (map_id, key)
    html, oldhtml = (REF / 'index.html').read_text(), merge.baseline('docs/reference/index.html').decode()
    art = json.loads((REF / 'art/manifest.json').read_text())
    assert builder.build(old, art) == oldhtml, 'Backward-compatible builder must exactly regenerate old index'
    assert builder.build(data, art) == html
    current_cards, old_cards = cards(html), cards(oldhtml)
    assert set(current_cards) == set(old_cards)
    changed = {key for key in old_cards if old_cards[key] != current_cards[key]}
    intended = {'maps-' + key for key in current['maps']} | {'rules-exploration_maps'}
    assert changed == intended, changed
    assert '三个怪群' not in current_cards['town_services-map_device'] and '3处' not in current_cards['town_services-map_device']
    page = Page(); page.feed(html)
    assert len(page.ids) == len(set(page.ids))
    for link in page.links:
        if link.startswith('#'): assert link[1:] in page.ids, link
        elif not re.match(r'^[a-z]+:', link): assert (REF / link.split('#')[0]).resolve().exists(), link
    for asset in page.assets:
        if not re.match(r'^[a-z]+:', asset): assert (REF / asset).is_file(), asset
    evidence = {}
    for key in ['layout_test', 'actual_main_report', 'tested_inputs']:
        source = current[key]
        assert sha(ROOT / source['path']) == source['sha256'], key
        evidence[key] = source
    inputs = json.loads((ROOT / current['tested_inputs']['path']).read_text())
    for path, digest in inputs.items(): assert sha(ROOT / path) == digest, path
    report = json.loads((ROOT / current['actual_main_report']['path']).read_text())
    layout_report = json.loads((ROOT / current['layout_test']['path']).read_text())
    assert report['checks'] == current['actual_main_checks'] == 185 and report['failures'] == current['actual_main_failures'] == 0
    assert layout_report['checks'] == current['layout_checks'] == 28135 and layout_report['failures'] == 0
    assert len(layout_report['plans']) == current['layout_configurations'] == 36
    assert {(row['map'], row['tier'], row['seed']) for row in layout_report['plans']} == {(map_id, tier, seed) for map_id in current['maps'] for tier in [1, 2, 3] for seed in [90001, 90002, 90003]}
    assert all(row['same_roster'] and row['outposts'] == 6 for row in layout_report['plans'])
    layouts = {}
    for map_id, entry in current['maps'].items():
        card = current_cards['maps-' + map_id]
        parsed = Page(); parsed.feed(card)
        shape, plan = entry['geometry'], entry['plan_example']
        marks = shape['landmarks']
        assert shape['bounds']['size'] == [3600, 2400]
        assert [float(v) for v in parsed.layout['viewbox'].split()] == shape['bounds']['position'] + shape['bounds']['size']
        assert marks['distribution_version'] == 'route_outposts_v1'
        assert len(marks['outposts']) == 6 and len(marks['camps']) == 3
        assert [site['root_count'] for site in marks['outposts']] == ([3, 5] if map_id == 'old_garden' else [4, 8]) * 3
        assert len(parsed.routes) == len(marks['route_segments'])
        for index, segment in enumerate(marks['route_segments']):
            route = parsed.routes[str(index)]
            assert [float(route[k]) for k in ['x1', 'y1', 'x2', 'y2']] == segment['from'] + segment['to']
            assert float(route['stroke-width']) == segment['width'] == 72.0
        assert len(parsed.walls) == len(shape['walls'])
        for index, wall in enumerate(shape['walls']):
            assert [float(parsed.walls[str(index)][k]) for k in ['x', 'y', 'width', 'height']] == wall['position'] + wall['size']
        assert set(parsed.signs) == {site['id'] for site in marks['outposts']} | {'boss'}
        for site in marks['outposts'] + [{**marks['boss'], 'id': 'boss'}]:
            x, y = site['sign_position']
            assert parsed.signs[site['id']]['d'] == f'M{x} {y-20}v40M{x-20} {y-20}h40v22h-40z'
        assert [float(parsed.entry[k]) for k in ['cx', 'cy']] == marks['entry']
        assert len(parsed.spawns) == plan['total'] == entry['ordinary_target'] + 1
        assert plan['mechanism_config'] == {} and plan['optional_encounters'] == []
        positions = {}
        for root, record in zip(plan['roots'], plan['spawn_records'], strict=True):
            assert root['actor_id'] == root['root_id'] == record['actor_id'] == record['root_id']
            assert not root['awake'] and root['reward_eligible'] and root['generation'] == 0
            assert root['position'] == record['position'] and root['outpost_id'] == record['outpost_id']
            assert record['encounter_id'] == '' and record['reward_route'] == 'standard'
            dot = parsed.spawns[record['spawn_key']]
            assert [float(dot[k]) for k in ['cx', 'cy']] == record['position']
            assert dot['data-template'] == record['template_id']
            positions[record['source_group'], record['ordinal']] = record['position'], record['outpost_id']
        for site in marks['outposts']:
            members = [r for r in plan['spawn_records'] if r['outpost_id'] == site['id']]
            assert len(members) == site['root_count']
            assert [r['ordinal'] for r in members] == site['ordinals']
            assert [r['position'] for r in members] == site['positions']
        actual = entry['actual_main_entry']
        if map_id == 'old_garden':
            assert actual['report_record_path'] == 'full_run.records' and 'entry' not in actual
            assert actual['spawn_records'] == report['full_run']['records']
            assert actual['actor_ids'] == [row['actor_id'] for row in report['full_run']['records']]
        else:
            index, observed = next((i, row) for i, row in enumerate(report['entries']) if row['map_id'] == map_id)
            assert actual['report_record_path'] == f'entries[{index}]'
            assert actual['spawn_records'] == observed['records'] and actual['actor_ids'] == observed['ids'] and actual['entry'] == observed['entry']
        for record in actual['spawn_records']:
            assert ([float(v) for v in record['position'][1:-1].split(', ')], record['outpost_id']) == positions[record['source_group'], record['ordinal']]
        for stale in ['三个怪群可任意顺序', '靠近木牌64', '全部普通根怪死亡后开启', '进入木牌 ', '整组等待']:
            assert stale not in card, (map_id, stale)
        assert '六处驻点' in card and '原3个来源组' in card
        layouts[map_id] = {'route_segments': len(parsed.routes), 'actual_route_width': 72, 'outpost_signs': 6, 'boss_signs': 1, 'initial_entities': len(parsed.spawns), 'main_record_path': actual['report_record_path']}
    result = {'ok': True, 'baseline_commit': merge.BASE, 'preserved_raw_top_level_count': len(data) - 1,
              'preserved_map_economy_and_boss_raw_tokens': True, 'backward_compatible_builder_old_catalog_exact': True,
              'changed_cards_only': sorted(changed), 'unchanged_card_count': len(old_cards) - len(changed),
              'layouts': layouts, 'all_local_links_and_assets_resolve': True, 'duplicate_anchors': False,
              'frozen_production_and_document_count': len(frozen['production']), 'frozen_production_and_documents_unchanged': True,
              'protected_reference_file_count': len(protected_now), 'protected_png_count': sum(p.endswith('.png') for p in protected_now),
              'protected_reference_bytes_and_mtime_unchanged': True, 'no_new_pngs': True,
              'evidence': evidence, 'tested_input_count': len(inputs), 'tested_inputs_match': True,
              'build_matches': True, 'game_version_preserved': data['game_version'],
              'current_output_sha256': {str(p.relative_to(ROOT)): sha(p) for p in [ROOT / 'tools/build_reference.py', REF / 'catalog.json', REF / 'index.html']},
              'scope': 'Output/source/provenance only; no production test rerun, Main, combat, native F8 visual or release validation.'}
    (QA / 'preservation.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__': main()

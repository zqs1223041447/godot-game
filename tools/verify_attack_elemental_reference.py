#!/usr/bin/env python3
"""Bounded generated-data/card preservation check against the pre-refresh snapshot."""
import json
import re
import subprocess
from pathlib import Path
from urllib.parse import unquote, urlsplit

from merge_attack_elemental_reference import IDS, LINE, ROOT, merge

BASE = '2235f079c6140176cd2c374ac1857bbc68690a7f'
REF = ROOT / 'docs/reference'


def original(path):
    return subprocess.check_output(['git', 'show', f'{BASE}:{path}'], cwd=ROOT).decode()


def verify():
    fragment = json.loads((ROOT / 'docs/qa/attack-elemental-reference/fragment.json').read_text())
    before_text = original('docs/reference/catalog.json')
    after = json.loads((REF / 'catalog.json').read_text())
    assert after == json.loads(merge(before_text, fragment))
    assert after['canonical'] == json.loads(before_text)['canonical'], 'Historical canonical snapshot drifted'
    pattern = r'<article\b[^>]*\bid="([^"]+)"[^>]*>.*?</article>'
    old_html = original('docs/reference/index.html')
    html = (REF / 'index.html').read_text()
    old_cards = {m[1]: m[0] for m in re.finditer(pattern, old_html, re.S)}
    cards = {m[1]: m[0] for m in re.finditer(pattern, html, re.S)}
    assert cards.keys() == old_cards.keys()
    targets = {'source_passives-' + key for key in IDS}
    metadata_changes = set()
    for key in cards.keys() - targets:
        expected = old_cards[key].replace('当前存档结构 53；', '当前存档结构 55；')
        expected = expected.replace('当前存档 53；当前源执行政策 49。', '当前存档 55；当前源执行政策 55。')
        expected = expected.replace('当前存档53、源政策49及开放范围', '当前存档55、源政策55及开放范围')
        assert cards[key] == expected, ('Unrelated card changed', key)
        if expected != old_cards[key]:
            metadata_changes.add(key)
    all_ids = set(re.findall(r'\bid="([^"]+)"', html))
    link_count = 0
    for key in targets | metadata_changes:
        card = cards[key]
        for href in re.findall(r'(?:href|src)="([^"]+)"', card):
            parsed = urlsplit(href)
            if parsed.scheme or parsed.netloc:
                continue
            if not parsed.path:
                assert unquote(parsed.fragment) in all_ids, (key, href)
            else:
                assert (REF / unquote(parsed.path)).is_file(), (key, href)
            link_count += 1
    for key in targets:
        assert '暂未实装' not in cards[key] and '未实现的源效果' not in cards[key]
        assert '攻击技能造成的元素伤害提高12%' in cards[key]
        assert '<span class="status implemented">已实现</span>' in cards[key]
    assert '不能普通连线分配' in cards['source_passives-18670']
    assert '特殊珠宝准入需另行验证' in cards['source_passives-18670']
    for key in IDS - {'18670'}:
        assert '仍需合法连接、点数和位置资格' in cards['source_passives-' + key]
    coverage = json.loads((REF / 'source-tree-coverage.json').read_text())
    old_coverage = json.loads(original('docs/reference/source-tree-coverage.json'))
    assert coverage.keys() == old_coverage.keys()
    assert {k for k in coverage if coverage[k] != old_coverage[k]} == {'nodes', 'effect_coverage', 'class_reachability'}
    old_nodes = {node['id']: node for node in old_coverage['nodes']}
    changed = {node['id'] for node in coverage['nodes'] if node != old_nodes[node['id']]}
    assert changed == IDS
    for route, old_route in zip(coverage['class_reachability'], old_coverage['class_reachability']):
        assert set(route['reachable_node_ids_including_start']) - set(old_route['reachable_node_ids_including_start']) == IDS - {'18670'}
        assert set(old_route['reachable_node_ids_including_start']) <= set(route['reachable_node_ids_including_start'])
    assert after['source_tree_localization']['lines'][LINE]['status']['implemented']
    return {'ok': True, 'baseline': BASE, 'target_cards': sorted(targets),
            'current_provenance_only_cards': sorted(metadata_changes),
            'other_cards_byte_identical': len(cards) - len(targets) - len(metadata_changes),
            'checked_local_links': link_count, 'coverage_changed_nodes': sorted(changed),
            'ordinary_reachable_nodes_per_class': [route['reachable_count_including_start'] for route in coverage['class_reachability']],
            'boundaries': 'Static data, generation and local links only; no browser interaction, combat or migration suites rerun; special-jewel admission unverified.'}


if __name__ == '__main__':
    print(json.dumps(verify(), ensure_ascii=False, indent=2))

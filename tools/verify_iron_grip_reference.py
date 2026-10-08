#!/usr/bin/env python3
"""Static related-card/reference preservation; no repeated gameplay runs."""
import hashlib
import json
import re
import subprocess
from urllib.parse import unquote, urlsplit
from build_reference import build
from merge_iron_grip_reference import ROOT, QA, LINE, merge

BASE = '904fd5e5e61f8169dda07e91566364d6bd42bfb6'
REF = ROOT / 'docs/reference'


def original(path):
    return subprocess.check_output(['git', 'show', BASE+':'+path], cwd=ROOT).decode()


def verify():
    fragment = json.loads((QA/'reference-fragment.json').read_text())
    old_text = original('docs/reference/catalog.json')
    old = json.loads(old_text)
    text = (REF/'catalog.json').read_text()
    current = json.loads(text)
    assert text == merge(old_text, fragment) == merge(text, fragment)
    assert current['source_tree']['nodes']['12926']['execution']['grants'] == [{'stat':'iron_grip','mode':'flat','value':1}]
    assert current['source_tree_localization']['lines'][LINE]['status']['implemented']
    assert current['canonical'] == old['canonical']
    html = (REF/'index.html').read_text()
    assert html == build(current, json.loads((REF/'art/manifest.json').read_text()))
    pattern = r'<article\b[^>]*\bid="([^"]+)"[^>]*>.*?</article>'
    cards = {m[1]:m[0] for m in re.finditer(pattern, html, re.S)}
    old_cards = {m[1]:m[0] for m in re.finditer(pattern, original('docs/reference/index.html'), re.S)}
    assert cards.keys() == old_cards.keys()
    changed = {key for key in cards if cards[key] != old_cards[key]}
    rules = {'rules-equipment', 'rules-source_tree', 'rules-source_monster_movement', 'rules-source_monster_damage_life',
             'rules-source_monster_shield_recharge', 'rules-frost_lock', 'rules-elemental_conversion', 'rules-physical_fire_conversion'}
    assert changed == rules | {'source_passives-12926', 'rules-source_defenses'}, changed
    for key in rules - {'rules-source_tree'}:
        wanted = old_cards[key].replace('当前存档结构 56；','当前存档结构 57；').replace('当前存档56、源政策56及开放范围','当前存档57、源政策57及开放范围')
        assert cards[key] == wanted, key
    target = cards['source_passives-12926']
    assert '暂未实装' not in target and '双标签只计一次' in target and '普通游侠路线（起点免费，共14点）' in target
    for phrase in ['物理转换', '新增纯元素伤害', '飞行中的攻击保留快照', '旧56继续拒绝']: assert phrase in target, phrase
    for phrase in ['当前57', '完整验证冻结旧56', '.v56-backup.json', '旧56程序拒绝57文件', '备份不含升级后进度', '不承诺任意并发时序或断电级持久性']:
        assert phrase in cards['rules-source_tree'], phrase
    ids = set(re.findall(r'\bid="([^"]+)"', html))
    links = 0
    for key in changed:
        for href in re.findall(r'(?:href|src)="([^"]+)"', cards[key]):
            parsed = urlsplit(href)
            if parsed.scheme or parsed.netloc: continue
            if not parsed.path: assert unquote(parsed.fragment) in ids, (key, href)
            else: assert (REF/unquote(parsed.path)).is_file(), (key, href)
            links += 1
    coverage = json.loads((REF/'source-tree-coverage.json').read_text())
    prior = json.loads(original('docs/reference/source-tree-coverage.json'))
    old_nodes = {node['id']:node for node in prior['nodes']}
    assert {node['id'] for node in coverage['nodes'] if node != old_nodes[node['id']]} == {'12926'}
    assert {k for k in coverage if coverage[k] != prior[k]} == {'nodes','effect_coverage','class_reachability'}
    for current_route, prior_route in zip(coverage['class_reachability'], prior['class_reachability']):
        new_set = set(current_route['reachable_node_ids_including_start'])
        old_set = set(prior_route['reachable_node_ids_including_start'])
        assert new_set - old_set == {'12926'} and old_set <= new_set
    paths = ['docs/reference/catalog.json','docs/reference/index.html','docs/reference/source-tree-coverage.json',
             'tools/build_reference.py','tools/iron_grip_reference.gd','tools/merge_iron_grip_reference.py','tools/verify_iron_grip_reference.py']
    return {'ok':True,'baseline':BASE,'changed_cards':sorted(changed),'other_cards_byte_identical':len(cards)-len(changed),
            'checked_related_local_links':links,'coverage_changed_nodes':['12926'],'new_ordinary_reachable_ids':['12926'],
            'sha256':{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths}}


if __name__ == '__main__':
    result = verify()
    (QA/'reference-verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps(result, ensure_ascii=False, indent=2))

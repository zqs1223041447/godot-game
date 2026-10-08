#!/usr/bin/env python3
"""Verify the bounded F8 merge against the reviewed pre-CI baseline."""
import hashlib
import json
import re
import subprocess
from urllib.parse import unquote, urlsplit
from build_reference import build
from merge_chaos_inoculation_reference import ROOT, QA, LINE, merge

BASE = 'c74596e5a268000a4988d779c5517f712b55afe2'
REF = ROOT / 'docs/reference'


def original(path):
    return subprocess.check_output(['git', 'show', BASE+':'+path], cwd=ROOT).decode()


def verify():
    fragment = json.loads((QA/'reference-fragment.json').read_text())
    old_text = original('docs/reference/catalog.json')
    before = json.loads(old_text)
    text = (REF/'catalog.json').read_text()
    current = json.loads(text)
    assert text == merge(old_text, fragment) == merge(text, fragment)
    assert current['source_tree']['nodes']['11455']['execution']['grants'] == [{'stat':'chaos_inoculation','mode':'flat','value':1}]
    assert current['source_tree_localization']['lines'][LINE]['status']['implemented']
    assert current['canonical'] == before['canonical']
    html = (REF/'index.html').read_text()
    assert html == build(current, json.loads((REF/'art/manifest.json').read_text()))
    pattern = r'<article\b[^>]*\bid="([^"]+)"[^>]*>.*?</article>'
    cards = {m[1]:m[0] for m in re.finditer(pattern, html, re.S)}
    old_cards = {m[1]:m[0] for m in re.finditer(pattern, original('docs/reference/index.html'), re.S)}
    assert cards.keys() == old_cards.keys()
    changed = {key for key in cards if cards[key] != old_cards[key]}
    provenance = {'rules-equipment','rules-source_monster_movement','rules-source_monster_damage_life',
                  'rules-source_monster_shield_recharge','rules-frost_lock','rules-elemental_conversion','rules-physical_fire_conversion'}
    assert changed == provenance | {'rules-source_tree','rules-source_defenses','source_passives-11455'}, changed
    for key in provenance:
        assert cards[key] == old_cards[key].replace('当前存档结构 58；','当前存档结构 59；').replace('当前存档58、源政策58及开放范围','当前存档59、源政策59及开放范围'), key
    target = cards['source_passives-11455']
    for phrase in ['最终最大生命固定为1','不是提高混沌抗性','本游戏混沌原本不绕盾','普通女巫路线（起点免费，共11点）','退款恢复容量但不免费补血','纯免疫保留原伤害/减免记录']:
        assert phrase in target, phrase
    assert '暂未实装' not in target
    for phrase in ['当前59先完整验证冻结旧58','.v58-backup.json','57→58保持固定终点','旧58程序拒绝59文件','备份不含升级后的进度']:
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
    assert {node['id'] for node in coverage['nodes'] if node != old_nodes[node['id']]} == {'11455'}
    assert {k for k in coverage if coverage[k] != prior[k]} == {'nodes','effect_coverage','class_reachability'}
    for now, old in zip(coverage['class_reachability'], prior['class_reachability']):
        new_set = set(now['reachable_node_ids_including_start'])
        old_set = set(old['reachable_node_ids_including_start'])
        assert new_set - old_set == {'11455'} and old_set <= new_set
    frozen = ['data/passive_source/data.json','data/passive_source/normalized_tree.json','data/passive_source/localization_zh_CN.json',
              'data/passives/official_tree_runtime.json','scripts/combat/leech_runtime.gd','scripts/combat/leech_rules.gd',
              'scripts/combat/damage_resolver.gd','scripts/items/equipment_catalog.gd']
    for path in frozen: assert (ROOT/path).read_bytes() == subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT), path
    report = {'baseline':BASE,'changed_cards':sorted(changed),'unchanged_cards':len(cards)-len(changed),
              'checked_related_links':links,'coverage_changed_nodes':['11455'],'frozen_source_and_other_systems':frozen,
              'catalog_sha256':hashlib.sha256(text.encode()).hexdigest(),'html_sha256':hashlib.sha256(html.encode()).hexdigest()}
    (QA/'reference-verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report,ensure_ascii=False))


if __name__ == '__main__': verify()

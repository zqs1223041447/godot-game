#!/usr/bin/env python3
"""Related F8 cards and bounded export only; no runtime test suite."""
import hashlib
import json
import re
import subprocess
from urllib.parse import unquote, urlsplit
from build_reference import build
from merge_one_with_nature_reference import ROOT, QA, LINE, merge

BASE = 'dbfbbf42457fe3f49a50fe232b5411c1e37c9f72'
REF = ROOT / 'docs/reference'
TARGETS = {'source_passives-15842','source_passives-18670','source_passives-30894'}
RULES = {'rules-equipment','rules-source_tree','rules-source_monster_movement',
         'rules-source_monster_damage_life','rules-source_monster_shield_recharge',
         'rules-frost_lock','rules-elemental_conversion','rules-physical_fire_conversion'}


def original(path):
    return subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT).decode()


def verify():
    fragment = json.loads((QA/'fragment.json').read_text())
    before_text = original('docs/reference/catalog.json')
    before = json.loads(before_text)
    text = (REF/'catalog.json').read_text()
    after = json.loads(text)
    assert text == merge(before_text,fragment), 'Catalog exceeds bounded changes'
    assert text == merge(text,fragment), 'Bounded merge is not idempotent'
    assert after['canonical'] == before['canonical'] and after['canonical']['save_version'] == 47
    node = after['source_tree']['nodes']['15842']
    assert node['execution']['status'] == 'full' and not node['execution']['unsupported']
    assert node['execution']['grants'][:-1] == before['source_tree']['nodes']['15842']['execution']['grants'], 'Original resistance/critical grants drifted'
    assert node['execution']['grants'][-1] == {'stat':'attack_elemental_increased','value':0.24,'mode':'increased'}
    assert after['source_tree_localization']['nodes']['15842']['name'] == '与自然合一'
    assert after['source_tree_localization']['lines'][LINE]['status']['implemented']
    assert after['source_tree']['nodes']['37504']['execution'] == before['source_tree']['nodes']['37504']['execution'], 'Unimplemented neighbor was opened'
    html = (REF/'index.html').read_text()
    assert html == build(after,json.loads((REF/'art/manifest.json').read_text())), 'Related card generation is stale'
    pattern = r'<article\b[^>]*\bid="([^"]+)"[^>]*>.*?</article>'
    old_cards = {m[1]:m[0] for m in re.finditer(pattern,original('docs/reference/index.html'),re.S)}
    cards = {m[1]:m[0] for m in re.finditer(pattern,html,re.S)}
    assert cards.keys() == old_cards.keys()
    changed = {key for key in cards if cards[key] != old_cards[key]}
    assert changed == TARGETS | RULES, ('Unexpected changed cards',changed)
    for key in cards.keys() - changed: assert cards[key] == old_cards[key]
    for key in RULES - {'rules-source_tree'}:
        expected = old_cards[key].replace('当前存档结构 55；','当前存档结构 56；')
        expected = expected.replace('当前存档55、源政策55及开放范围','当前存档56、源政策56及开放范围')
        assert cards[key] == expected, ('Rule changed beyond current provenance',key)
    assert cards['source_passives-30894'] == old_cards['source_passives-30894'].replace('一与自然','与自然合一')
    assert '暂未实装' not in cards['source_passives-15842'] and '未实现的源效果' not in cards['source_passives-15842']
    assert '已实装精确24%攻击元素INC' in cards['source_passives-15842'] and '原全元素抗性+8%和攻击暴击率提高24%保持' in cards['source_passives-15842']
    assert '仍需合法连接、点数和位置资格' in cards['source_passives-18670'] and '不能普通连线分配' not in cards['source_passives-18670']
    assert '暂未实装' in cards['source_passives-37504'] and '整节点锁定' in cards['source_passives-37504']
    for phrase in ['当前存档 56；当前源执行政策 56','完整验证冻结旧55','.v55-backup.json','仅改变版本','失败不发布新构筑','不等于恢复整场战斗','旧55程序拒绝56文件','备份不含升级后进度','不承诺覆盖任意并发时序或断电级持久性']:
        assert phrase in cards['rules-source_tree'],phrase
    ids = set(re.findall(r'\bid="([^"]+)"',html)); links = 0
    for key in changed:
        for href in re.findall(r'(?:href|src)="([^"]+)"',cards[key]):
            parsed = urlsplit(href)
            if parsed.scheme or parsed.netloc: continue
            if not parsed.path: assert unquote(parsed.fragment) in ids,(key,href)
            else: assert (REF/unquote(parsed.path)).is_file(),(key,href)
            links += 1
    coverage = json.loads((REF/'source-tree-coverage.json').read_text())
    old_coverage = json.loads(original('docs/reference/source-tree-coverage.json'))
    assert coverage.keys() == old_coverage.keys()
    assert {k for k in coverage if coverage[k] != old_coverage[k]} == {'nodes','effect_coverage','class_reachability'}
    old_nodes = {n['id']:n for n in old_coverage['nodes']}
    assert {n['id'] for n in coverage['nodes'] if n != old_nodes[n['id']]} == {'15842'}
    for new_route,old_route in zip(coverage['class_reachability'],old_coverage['class_reachability']):
        assert new_route['class_id'] == old_route['class_id']
        assert set(new_route['reachable_node_ids_including_start']) - set(old_route['reachable_node_ids_including_start']) == {'15842','18670'}
        assert set(old_route['reachable_node_ids_including_start']) <= set(new_route['reachable_node_ids_including_start'])
    runtime = ['data/passive_source/localization_zh_CN.json'] + subprocess.check_output(['git','ls-tree','-r','--name-only',BASE,'scripts','assets','scenes','project.godot'],cwd=ROOT,text=True).splitlines()
    for path in runtime:
        assert (ROOT/path).read_bytes() == subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT), ('Runtime changed',path)
    paths = ['docs/reference/catalog.json','docs/reference/index.html','docs/reference/source-tree-coverage.json',
             'tools/build_reference.py','tools/one_with_nature_reference.gd','tools/merge_one_with_nature_reference.py',
             'tools/verify_one_with_nature_reference.py','docs/qa/one-with-nature-reference/fragment.json']
    hashes = {p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths}
    return {'ok':True,'baseline':BASE,'effect_cards':['source_passives-15842'],
            'directly_related_existing_cards':['source_passives-18670','source_passives-30894'],
            'current_rule_cards':sorted(RULES),'other_cards_byte_identical':len(cards)-len(changed),
            'checked_related_local_links':links,'coverage_changed_nodes':['15842'],
            'new_ordinary_reachable_ids':['15842','18670'],'reachable_count_per_class':[r['reachable_count_including_start'] for r in coverage['class_reachability']],
            'source_sha256':hashes,'runtime_files_byte_identical':len(runtime),
            'boundaries':'Read-only source export, related card generation/preservation and local links only; no transaction/combat suites, browser interaction or full battle restoration claim.'}


if __name__ == '__main__':
    result = verify()
    (QA/'verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(result,ensure_ascii=False,indent=2))

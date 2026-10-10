#!/usr/bin/env python3
"""Exact bounded F8 refresh; reject any unrelated source execution/card change."""
import hashlib
import json
import re
import subprocess
from urllib.parse import unquote, urlsplit
from build_reference import build
from merge_arcane_will_reference import ROOT, QA, LINE, merge
from merge_ruins_garden_reference import member_span

BASE='cdaee678322da0298e7b3e774a92ba62e2327c4d'
REF=ROOT/'docs/reference'
def original(path):
    return subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT).decode()
def verify():
    fragment=json.loads((QA/'reference-fragment.json').read_text())
    old_text=original('docs/reference/catalog.json'); before=json.loads(old_text)
    text=(REF/'catalog.json').read_text(); current=json.loads(text)
    assert text==merge(old_text,fragment)==merge(text,fragment), 'Merge must preserve untouched bytes and be idempotent'
    assert current['save_version']==current['source_tree']['source_policy']==61
    assert current['source_tree']['nodes']['27163']['execution']['grants']==[
        {'stat':'max_mana','mode':'increased','value':0.3},
        {'stat':'mana_regen','mode':'flat','value':5},
        {'stat':'intelligence','mode':'flat','value':10}]
    assert not current['source_tree_localization']['lines'][LINE]['status']['implemented']
    assert current['arcane_will']['line_status']['implemented']
    for container in ['source_tree','source_tree_localization']:
        assert {k for k in current[container]['nodes'] if current[container]['nodes'][k]!=before[container]['nodes'][k]}=={'27163'}
    assert {k for k in current['source_tree_localization']['lines'] if current['source_tree_localization']['lines'][k]!=before['source_tree_localization']['lines'][k]}==set()
    # Exact merge(old_text, fragment) above proves byte preservation outside the declared spans.
    # Independently check important historical roots without repeated whole-file scanning.
    for key in ['canonical','equipment','chaos_defense','purity_of_flesh']:
        a,b=member_span(old_text,[key]); c,d=member_span(text,[key])
        assert old_text[a:b]==text[c:d], 'Existing catalog value bytes changed: '+key
    assert current['canonical']==before['canonical']
    art=json.loads((REF/'art/manifest.json').read_text())
    html=(REF/'index.html').read_text(); old_html=original('docs/reference/index.html')
    assert html==build(current,art), 'Current HTML must match checked-in generator'
    assert old_html==build(before,art), 'New generator must reproduce all old cards when given old data'
    pattern=r'<article\b[^>]*\bid="([^"]+)"[^>]*>.*?</article>'
    cards={m[1]:m[0] for m in re.finditer(pattern,html,re.S)}
    old_cards={m[1]:m[0] for m in re.finditer(pattern,old_html,re.S)}
    assert cards.keys()==old_cards.keys()
    changed={key for key in cards if cards[key]!=old_cards[key]}
    provenance={'rules-equipment','rules-source_monster_movement','rules-source_monster_damage_life',
                'rules-source_monster_shield_recharge','rules-frost_lock','rules-elemental_conversion','rules-physical_fire_conversion'}
    assert changed==provenance|{'source_passives-27163','rules-source_tree','rules-character_rates'}, changed
    for key in provenance:
        assert cards[key]==old_cards[key].replace('当前存档结构 60；','当前存档结构 61；').replace('当前存档60、源政策60及开放范围','当前存档61、源政策61及开放范围'),key
    target=cards['source_passives-27163']
    for phrase in ['最大魔力提高30%','智慧+10','每秒','普通女巫路线（起点免费，共8点）','12处同句魔力专精继续锁定','旧60仍拒绝整个节点']:
        assert phrase in target,phrase
    assert '暂未实装' not in target
    for phrase in ['当前61','60→61','.v60-backup.json','59→60仍为固定单步']:
        assert phrase in cards['rules-source_tree'],phrase
    blocked_masteries=[]
    for key,node in before['source_tree']['nodes'].items():
        for option in node['mastery_choices']:
            if LINE in option['stats']:
                assert current['source_tree']['nodes'][key]==node
                assert cards['source_passives-'+key]==old_cards['source_passives-'+key]
                blocked_masteries.append(key)
    assert len(blocked_masteries)==12
    ids=set(re.findall(r'\bid="([^"]+)"',html)); links=0
    for key in changed:
        for href in re.findall(r'(?:href|src)="([^"]+)"',cards[key]):
            parsed=urlsplit(href)
            if parsed.scheme or parsed.netloc:continue
            if not parsed.path:assert unquote(parsed.fragment) in ids,(key,href)
            else:assert (REF/unquote(parsed.path)).is_file(),(key,href)
            links+=1
    pattern=r'<script id="reference-data" type="application/json">(.*?)</script>'
    search=json.loads(re.search(pattern,html,re.S)[1]); old_search=json.loads(re.search(pattern,old_html,re.S)[1])
    assert search.keys()==old_search.keys()
    # Inspect the generated search container while retaining all other UI payloads.
    changed_payload=[key for key in search if search[key]!=old_search[key]]
    assert changed_payload==['records']
    prior_records={row['id']:row for row in old_search['records']}; now_records={row['id']:row for row in search['records']}
    assert prior_records.keys()==now_records.keys()
    assert {key for key in now_records if now_records[key]!=prior_records[key]}==changed
    for key in changed:
        fields={field for field in now_records[key] if now_records[key][field]!=prior_records[key][field]}
        assert fields==({'search','status'} if key=='source_passives-27163' else {'search'}), (key,fields)
    coverage=json.loads((REF/'source-tree-coverage.json').read_text()); prior=json.loads(original('docs/reference/source-tree-coverage.json'))
    old_nodes={node['id']:node for node in prior['nodes']}
    assert {node['id'] for node in coverage['nodes'] if node!=old_nodes[node['id']]}=={'27163'}
    assert {key for key in coverage if coverage[key]!=prior[key]}=={'nodes','effect_coverage','class_reachability'}
    for now,old in zip(coverage['class_reachability'],prior['class_reachability']):
        new_set=set(now['reachable_node_ids_including_start']);old_set=set(old['reachable_node_ids_including_start'])
        assert new_set-old_set=={'27163'} and old_set<=new_set
    assert coverage==json.loads((QA/'source-tree-coverage.json').read_text())
    frozen=['data/passive_source/data.json','data/passive_source/normalized_tree.json','data/passive_source/localization_zh_CN.json',
            'data/passives/official_tree_runtime.json','scripts/combat/damage_resolver.gd',
            'scripts/mechanics/defense_rules.gd','scripts/items/equipment_catalog.gd']
    for path in frozen:assert (ROOT/path).read_bytes()==subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT),path
    report={'baseline':BASE,'cards':len(cards),'changed_cards':sorted(changed),'unchanged_cards':len(cards)-len(changed),
            'provenance_only_cards':sorted(provenance),'checked_related_links':links,'changed_search_payload':changed_payload,
            'coverage_changed_nodes':['27163'],'identical_mana_masteries_still_blocked':blocked_masteries,'pinned_data_and_other_systems_unchanged':frozen,
            'catalog_sha256':hashlib.sha256(text.encode()).hexdigest(),'html_sha256':hashlib.sha256(html.encode()).hexdigest()}
    (QA/'reference-verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report,ensure_ascii=False))
if __name__=='__main__':verify()

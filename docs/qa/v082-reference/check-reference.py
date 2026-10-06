#!/usr/bin/env python3
"""Check v82 authoritative fragments and strict historical bytes; no combat model."""
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
BASE = 'a57a9c0'
LINE = '20% increased Duration of Cold Ailments'
STAT = 'cold_ailment_duration_increased'
spec = importlib.util.spec_from_file_location('merge_fragment', QA/'merge-fragment.py')
merge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(merge)

def sha(data):
    return hashlib.sha256(data).hexdigest()

def baseline(path):
    return subprocess.check_output(['git', 'show', BASE+':'+path], cwd=ROOT)

def near(actual, expected):
    assert math.isfinite(actual) and abs(actual-expected) <= 1e-12, (actual, expected)

class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids, self.links, self.assets, self.values = [], [], [], []
        self.active = None
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if 'id' in attrs: self.ids.append(attrs['id'])
        if 'href' in attrs: self.links.append(attrs['href'])
        if 'src' in attrs: self.assets.append(attrs['src'])
        if 'data-cold-duration-path' in attrs:
            self.values.append([attrs['data-cold-duration-path'],float(attrs['data-value']),''])
            self.active = len(self.values)-1
    def handle_data(self, text):
        if self.active is not None: self.values[self.active][2] += text
    def handle_endtag(self, tag):
        if tag == 'strong': self.active = None

def main():
    raw = (REF/'catalog.json').read_text()
    oldraw = baseline('docs/reference/catalog.json').decode()
    data, old = json.loads(raw), json.loads(oldraw)
    fragment = json.loads((QA/'cold-duration-fragment.json').read_text())
    proof = json.loads((QA/'catalog-format-preservation.json').read_text())
    rule = data['cold_ailment_duration']
    assert data['game_version']=='0.82.0'
    assert data['save_version']==data['source_tree']['source_policy']==rule['minimum_save_version']==rule['source_policy']==49
    assert rule['equipment_vocabulary']==46 and rule['level']==4 and rule['point_budget']==8
    assert rule['source_line']==LINE and rule['increased']==.2 and rule['max_targets']==100
    assert len(rule['route'])==len(set(rule['route']))==9 and rule['route'][-1]=='14209'
    assert set(data)==set(old)|{'cold_ailment_duration'} and rule==fragment['cold_ailment_duration']
    before, after = merge.spans(oldraw), merge.spans(raw)
    for key in proof['historical_raw_sections_preserved']:
        _,a,b = before[key]; _,c,d = after[key]
        assert oldraw[a:b]==raw[c:d], key
    assert len(proof['current_source_definition_metadata_changes'])==15
    for key, previous in old['mechanisms'].items():
        current = data['mechanisms'][key]
        if key in fragment['mechanisms']:
            current = {**current,'source_policy':48,'source_save_version':48,'policy_version':'source-tree:3.29.1:policy:48'}
        assert current==previous, key
    assert set(fragment['nodes'])=={'14209'}
    for key, previous in old['source_tree']['nodes'].items():
        current = data['source_tree']['nodes'][key]
        if key=='14209':
            assert current['execution']=={'grants':[{'stat':STAT,'mode':'increased','value':.2}],'status':'full','supported':[LINE],'unsupported':[]}
            assert {**current,'execution':previous['execution']}==previous
        else: assert current==previous, key
    assert data['source_tree_localization']['lines'][LINE]['status']['implemented']
    assert '暂未实装' not in data['source_tree_localization']['lines'][LINE]['text']
    assert data['source_tree_localization']['lines']['50% increased Duration of Cold Ailments']==old['source_tree_localization']['lines']['50% increased Duration of Cold Ailments']
    assert data['source_tree']['nodes']['21460']['execution']['status']=='partial'
    for key in ['fixture_helper','compiled_fixture','actual_main_report']:
        assert sha((ROOT/rule[key]).read_bytes())==rule[key+'_sha256'], key
    acceptance = json.loads((ROOT/rule['actual_main_report']).read_text())
    assert acceptance['checks']>0 and acceptance['failures']==0 and acceptance['sections']['compiled_and_preview']['failures']==0
    expected = json.loads((ROOT/rule['compiled_fixture']).read_text())
    assert len(rule['examples'])==6
    for name, entry in rule['examples'].items():
        assert sha((ROOT/entry['fixture']).read_bytes())==entry['fixture_sha256']
        fixture = json.loads((ROOT/entry['fixture']).read_text())
        original = expected[name]
        assert entry['whole_build_valid'] and entry['whole_cast_matches_main'] and entry['read_only_rebuilt'] and entry['save_attempts']==0
        assert fixture['version']==49 and fixture['progress']['level']==4
        assert fixture['talents']['allocated']==(rule['route'] if name.startswith('after-') else rule['route'][:-1])
        assert fixture['talents']['normal_points']==(0 if name.startswith('after-') else 1)
        assert entry['preview']==original['preview']
        for field in ['recipe','freeze_profile','mana','cooldown','initial_count']:
            assert entry[field]==original['cast'].get(field,{}), (name,field)
        near(entry['snapshot_increased'],.2 if name.startswith('after-') else 0)
    for name,before_slow,after_slow,supports in [('plain-frost',3,3.6,[]),('lingering-frost',4.5,5.4,['lingering_chill']),('frost-lock',3,3.6,['frost_lock'])]:
        a, b = (rule['examples'][stage+'-'+name] for stage in ['before','after'])
        near(a['recipe']['slow'],before_slow); near(b['recipe']['slow'],after_slow)
        assert a['support_ids']==b['support_ids']==supports
        assert {**b['recipe'],'slow':a['recipe']['slow']}==a['recipe']
        assert '现有减速时长 %.2f 秒'%after_slow in b['preview']
        for key in ['mana','cooldown','initial_count']: assert a[key]==b[key]
        before_fixture=json.loads((ROOT/a['fixture']).read_text());after_fixture=json.loads((ROOT/b['fixture']).read_text())
        assert {k:v for k,v in before_fixture.items() if k not in ['talents','revision']}=={k:v for k,v in after_fixture.items() if k not in ['talents','revision']}
    freeze=rule['examples']['after-frost-lock']['freeze_profile']
    for rarity,value in {'normal':.72,'magic':.72,'rare':.42,'boss':.24}.items(): near(freeze['duration_by_rarity'][rarity],value)
    near(freeze['immunity_seconds'],1.5);near(freeze['hit_multiplier'],.75);near(freeze['mana_multiplier'],1.2)
    coverage=json.loads((REF/'source-tree-coverage.json').read_text());prior=json.loads(baseline('docs/reference/source-tree-coverage.json'))
    assert (REF/'source-tree-coverage.json').read_bytes()==(QA/'source-tree-coverage.json').read_bytes()
    for key in prior:
        if key not in ['nodes','effect_coverage','class_reachability']: assert prior[key]==coverage[key],key
    nodes={n['id']:n for n in coverage['nodes']}
    assert [n['id'] for n in prior['nodes'] if n!=nodes[n['id']]]==['14209']
    for a,b in zip(prior['class_reachability'],coverage['class_reachability']):
        assert set(b['reachable_node_ids_including_start'])-set(a['reachable_node_ids_including_start'])=={'14209'}
        assert set(a['reachable_node_ids_including_start'])<=set(b['reachable_node_ids_including_start'])
        assert b['reachable_count_excluding_start']==a['reachable_count_excluding_start']+1==708
    html=(REF/'index.html').read_text();oldhtml=baseline('docs/reference/index.html').decode()
    page,oldpage=Page(),Page();page.feed(html);oldpage.feed(oldhtml)
    assert len(page.ids)==len(set(page.ids)) and set(page.ids)-set(oldpage.ids)=={'rules-cold_ailment_duration'} and set(oldpage.ids)<=set(page.ids)
    for path,actual,label in page.values:
        value=rule
        for field in path.split('/'): value=value[int(field)] if isinstance(value,list) else value[field]
        assert actual==value and label==format(value,'.12g'),(path,actual,label)
    assert len(page.values)==24
    for link in page.links:
        if link.startswith('#'): assert link[1:] in page.ids,link
        elif link and not link.startswith(('http:','https:','mailto:')): assert (REF/link.split('#')[0]).is_file(),link
    for asset in page.assets: assert not asset.startswith(('http:','https:')) and (REF/asset).is_file(),asset
    def cards(text): return {re.search(r'id="([^"]+)"',m).group(1):m for m in re.findall(r'<article\b.*?</article>',text,re.S)}
    oldcards,newcards=cards(oldhtml),cards(html)
    updated={'rules-source_tree','rules-elemental_conversion','rules-frost_lock','rules-physical_fire_conversion','rules-source_monster_movement','rules-source_monster_damage_life','rules-source_monster_shield_recharge','source_passives-14209'}|{'mechanisms-'+k for k in fragment['mechanisms']}
    preserved,labels=[],[]
    for key,value in oldcards.items():
        if key in updated: continue
        expected_card=value
        if key.startswith('supports-'): expected_card=expected_card.replace('运行版本 '+old['game_version'],'运行版本 '+data['game_version'])
        if key=='rules-equipment': expected_card=expected_card.replace('当前存档结构 '+str(old['save_version']),'当前存档结构 '+str(data['save_version']))
        assert expected_card==newcards[key],key
        (preserved if expected_card==value else labels).append(key)
    for key in updated-{'source_passives-14209','rules-source_tree'}-{'mechanisms-'+k for k in fragment['mechanisms']}:
        assert '当前存档49、源政策49' in newcards[key] and '#rules-cold_ailment_duration' in newcards[key],key
    protected={};pngs=[]
    tree=subprocess.check_output(['git','ls-tree','-r',BASE,'assets','data','docs/reference'],cwd=ROOT,text=True)
    for line in tree.splitlines():
        info,path=line.split('\t',1)
        if (path.startswith(('assets/','data/')) and path!='data/passive_source/localization_zh_CN.json') or path.endswith('.png') or path in ['docs/reference/reference.css','docs/reference/reference.js','docs/reference/art/manifest.json']:
            payload=(ROOT/path).read_bytes();blob=hashlib.sha1(b'blob '+str(len(payload)).encode()+b'\0'+payload).hexdigest()
            assert blob==info.split()[2],path
            protected[path]=sha(payload)
            if path.endswith('.png'): pngs.append(path)
    actual_pngs={str(p.relative_to(ROOT)) for folder in [ROOT/'assets',ROOT/'data',REF] for p in folder.rglob('*.png')}
    assert actual_pngs==set(pngs)
    result={'passed':True,'baseline_commit':BASE,'actual_main_fixtures':6,'exact_cast_and_preview_matches':6,'authoritative_html_values':len(page.values),'historical_raw_sections_preserved':proof['historical_raw_section_count'],'old_cards_byte_preserved':len(preserved),'version_label_only_cards':labels,'current_source_metadata_changes':15,'changed_source_nodes':['14209'],'reachable_non_start_nodes_per_class':708,'historical_source_actor_snapshots_preserved':True,'old_anchors_preserved':len(oldpage.ids),'new_anchor':'rules-cold_ailment_duration','protected_files':len(protected),'preserved_pngs':len(pngs),'all_links_and_assets_valid':True,'catalog_sha256':sha(raw.encode()),'html_sha256':sha(html.encode()),'coverage_sha256':sha((REF/'source-tree-coverage.json').read_bytes()),'scope':'One short runtime fragment; actual Main fixtures rebuilt read-only. No full export, historical runtime suite, new images, native UI, packages or release.'}
    with (QA/'preservation.json').open('x') as handle: json.dump(result,handle,ensure_ascii=False,indent=2);handle.write('\n')
    print(json.dumps(result,ensure_ascii=False,indent=2))

if __name__=='__main__': main()

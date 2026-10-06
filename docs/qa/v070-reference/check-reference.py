#!/usr/bin/env python3
"""One focused v70 fixture/projection check and strict baseline preservation."""
from copy import deepcopy
import hashlib,json,math,subprocess
from html.parser import HTMLParser
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3];QA=Path(__file__).resolve().parent;REF=ROOT/'docs/reference'
BASE='d25717c4485bf36688df36460f2c85ebb11b7623'
ENTRY='40% more Attack Damage if Accuracy Rating is higher than Maximum Life\nNever deal Critical Strikes'
GRANTS=[{'mode':'flat','stat':'precise_technique','value':1}]
MORE={'id':'precise_technique_attack_more','mode':'more','value':.4,'all_tags':['hit','attack'],'skills':[],'damage_types':[]}
NAMES=['selected-above','selected-below','refunded']
def sha(raw):return hashlib.sha256(raw).hexdigest()
def digest(value):return sha(json.dumps(value,sort_keys=True,ensure_ascii=False,separators=(',',':')).encode())
def oldbytes(path):return subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT)
def near(a,b):assert math.isfinite(a) and abs(a-b)<=max(1e-9,abs(b)*1e-10),(a,b)
def differences(a,b,p=()):
    if isinstance(a,dict) and isinstance(b,dict):
        for k in sorted(a.keys()|b.keys()):
            if k not in a:yield 'added',p+(k,),None,b[k]
            elif k not in b:yield 'removed',p+(k,),a[k],None
            else:yield from differences(a[k],b[k],p+(k,))
    elif isinstance(a,list) and isinstance(b,list) and len(a)==len(b):
        for i,(v,w) in enumerate(zip(a,b)):yield from differences(v,w,p+(i,))
    elif a!=b:yield 'changed',p,a,b
class Page(HTMLParser):
    def __init__(self):super().__init__();self.ids=[];self.links=[];self.assets=[];self.values={};self.labels={};self.active=None
    def handle_starttag(self,tag,attrs):
        a=dict(attrs)
        if 'id' in a:self.ids.append(a['id'])
        if 'href' in a:self.links.append(a['href'])
        if 'src' in a:self.assets.append(a['src'])
        if 'data-precise-value' in a:
            key=a['data-precise-value'];assert key not in self.values,key
            self.values[key]=float(a['data-value']);self.labels[key]='';self.active=key
    def handle_data(self,data):
        if self.active:self.labels[self.active]+=data
    def handle_endtag(self,tag):
        if tag=='strong':self.active=None

def setpath(obj,path,value):
    for key in path[:-1]:obj=obj[key]
    obj[path[-1]]=value

def main():
    old=json.loads(oldbytes('docs/reference/catalog.json'));data=json.loads((REF/'catalog.json').read_text());rule=data['precise_technique']
    assert data['game_version']=='0.70.0' and data['save_version']==rule['minimum_save_version']==rule['source_policy']==45
    assert rule['equipment_vocabulary']==39 and rule['node']['id']=='63620' and rule['node']['source_lines']==[ENTRY]
    assert rule['new_complete_ordinary_nodes']==['63620'] and rule['new_mastery_effect_ids']==rule['new_images']==[]
    assert rule['attack_more']==.4 and set(rule['examples'])==set(NAMES)
    assert rule['node']['execution']=={'status':'full','grants':GRANTS,'supported':[ENTRY],'unsupported':[]}
    acceptance=json.loads((ROOT/'docs/qa/v070-gameplay/acceptance.json').read_text());assert acceptance['passed']
    rendered={'save-version':45,'source-policy':45,'vocabulary':39,'attack-more':.4};casts=hits=0
    for name in NAMES:
        row=rule['examples'][name];raw=json.loads((ROOT/row['fixture']).read_text());expected=json.loads((ROOT/row['expected_fixture']).read_text())
        assert row['fixture']==f'docs/qa/v070-gameplay/fixtures/{name}.json'
        assert row['expected_fixture']==f'docs/qa/v070-gameplay/fixtures/{name}-expected.json'
        assert sha((ROOT/row['fixture']).read_bytes())==row['fixture_sha256']==acceptance['fixtures'][name+'.json']
        assert sha((ROOT/row['expected_fixture']).read_bytes())==row['expected_sha256']==acceptance['fixtures'][name+'-expected.json']
        assert row['stats']==expected['stats'] and row['talents']==raw['talents'] and row['progress']==raw['progress']
        assert row['whole_build_valid'] and row['matches_actual_main'] and row['save_attempts']==0
        assert row['stats']['accuracy']==284 and row['stats']['max_health']==(358 if name=='selected-below' else 141)
        for slot,equipment in row['equipment'].items():
            assert equipment['item']==raw['items'][equipment['uid']]
            assert raw['locations'][equipment['uid']]=={'kind':'equipment','slot_id':slot}
        selected=name!='refunded';condition=name=='selected-above'
        assert ('63620' in raw['talents']['allocated'])==selected
        for key,amount in [('accuracy',row['stats']['accuracy']),('max-health',row['stats']['max_health']),('attack-more',.4 if condition else 0),('save-attempts',0)]:rendered[name+'-'+key]=amount
        for skill in ['basic','cleave','tornado']:
            casts+=1;cast=row['casts'][skill]['compiled'];assert cast==expected[skill]
            assert not cast.get('hit_policy',{}).get('hits_cannot_be_evaded',False)
            modifiers=[m for m in cast['snapshot']['modifiers'] if m['id']=='precise_technique_attack_more']
            assert modifiers==([MORE] if condition else [])
            if selected:
                assert cast['snapshot']['precise_technique']=={'accuracy':284,'max_health':358 if name=='selected-below' else 141}
                assert cast['precise_technique_profile']=={'enabled':True,'accuracy':284,'max_health':358 if name=='selected-below' else 141,'condition_met':condition,'attack_more':.4 if condition else 0,'cannot_deal_critical_strikes':True,'attack_applies':condition}
            else:assert 'precise_technique' not in cast['snapshot'] and 'precise_technique_profile' not in cast
            for role,hit in row['casts'][skill]['hits'].items():
                hits+=1;key=name+'-'+skill+'-'+role
                assert hit['tags']==cast['packets'][role]['tags']
                assert hit['critical']==cast['critical']['secondary' if role=='secondary' else 'primary']
                if selected:assert hit['critical']['chance']==0
                else:assert hit['critical']['chance']==.05 and hit['critical']['multiplier']==1.5
                near(hit['resolved']['total'],sum(hit['resolved']['components'].values()))
                for kind in ['physical','fire']:rendered[key+'-'+kind]=hit['resolved']['components'].get(kind,0)
                rendered[key+'-total']=hit['resolved']['total'];rendered[key+'-critical-chance']=hit['critical']['chance'];rendered[key+'-critical-multiplier']=hit['critical']['multiplier']
    above=rule['examples']['selected-above'];refund=rule['examples']['refunded']
    assert above['equipment']==refund['equipment']
    for skill in ['basic','cleave','tornado']:
        for role,hit in above['casts'][skill]['hits'].items():
            other=refund['casts'][skill]['hits'][role];factor=1.4 if {'hit','attack'}<=set(hit['tags']) else 1
            assert above['casts'][skill]['compiled']['packets'][role]==refund['casts'][skill]['compiled']['packets'][role]
            for kind,amount in hit['resolved']['components'].items():near(amount,other['resolved']['components'][kind]*factor)
    page=Page();html=(REF/'index.html').read_text();page.feed(html)
    assert page.values.keys()==rendered.keys(),(page.values.keys()-rendered.keys(),rendered.keys()-page.values.keys())
    for key,value in rendered.items():near(page.values[key],value);assert page.labels[key].strip()==format(value,'.10g'),(key,page.labels[key],value)
    assert len(page.ids)==len(set(page.ids)) and 'rules-precise_technique' in page.ids
    oldpage=Page();oldpage.feed(oldbytes('docs/reference/index.html').decode());assert set(oldpage.ids)<=set(page.ids)
    for link in page.links:
        if link.startswith('#'):assert link[1:] in page.ids,link
        elif link and not link.startswith(('http:','https:','mailto:')):assert (REF/link.split('#')[0]).is_file(),link
    for asset in page.assets:assert not asset.startswith(('http:','https:')) and (REF/asset).is_file(),asset
    for wording in ['A严格大于L','等于或低于时为0','当前受伤生命不参与比较','所有攻击、法术及独立爆炸均不能暴击','不额外授予不能被闪避','裸装前置属性为A284、L141','v61/source38历史范围','当前source45已完整实现']:
        assert wording in html,wording
    assert '63620</a>的条件攻击伤害与其他任意多行效果仍未开放' not in html
    # Reconstruct every allowed old-catalog change, then compare the full tree.
    projected=deepcopy(old);projected['precise_technique']=rule;projected['game_version']='0.70.0'
    paths=[('save_version',),('canonical','default_build','version'),('canonical','save_version'),('crafting','calibration_shard','save_version'),('currencies','calibration_shard','save_version'),('melee_basic','save_version'),('normal_gem_trading','schema'),('sunwell_terrace','save_version'),('town_maps','save_version')]
    for op in ['augment','elevate','enchant','recalibrate','reforge','salvage','targeted_reforge_critical','targeted_reforge_damage','targeted_reforge_life_leech','targeted_reforge_mana_leech']:paths.append(('crafting',op,'example','save_version'))
    for path in paths:
        value=old
        for key in path:value=value[key]
        assert value==44;setpath(projected,path,45)
    for chapter in ['defense_rating_affixes','resolute_technique','elemental_defense_affixes','elemental_resistance_caps','iron_reflexes','zealots_oath','inward_pull','ambush','physical_fire_conversion']:
        assert old[chapter]['source_policy']==44;projected[chapter]['source_policy']=45
    projected['source_tree']['nodes']['63620']['execution']={'status':'full','grants':GRANTS,'supported':[ENTRY],'unsupported':[]}
    localized=projected['source_tree_localization']['nodes']['63620'];assert localized['stats'].endswith('（暂未实装）');localized['stats']=localized['stats'].removesuffix('（暂未实装）')
    line=projected['source_tree_localization']['lines'][ENTRY];line['text']=line['text'].removesuffix('（暂未实装）');line['status'].update(implemented=True,parser_supported=True,grants=GRANTS)
    assert projected==data,list(differences(projected,data))[:8]
    # 63620 is a leaf. Exactly one status transition and one new reachable node
    # per class are allowed; no arbitrary replacement of coverage subtrees.
    oldcoverage=json.loads(oldbytes('docs/reference/source-tree-coverage.json'));coverage=json.loads((REF/'source-tree-coverage.json').read_text());projected=deepcopy(oldcoverage)
    node=next(n for n in projected['nodes'] if n['id']=='63620');node['execution'].update(api_status='full',coverage_status='full',grants=GRANTS,supported=[ENTRY],unsupported=[])
    for partition in ['all_source','standard_allocation_graph']:
        for field in ['node_api_status_counts','node_direct_effect_status_counts','direct_effect_entries']:
            projected['effect_coverage'][partition][field]['full']+=1;projected['effect_coverage'][partition][field]['unsupported']-=1
    for route in projected['class_reachability']:
        assert sum(x['node_id']=='63620' for x in route['blocked_frontier'])==1
        route['blocked_frontier']=[x for x in route['blocked_frontier'] if x['node_id']!='63620'];route['blocked_frontier_count']-=1;route['blocked_frontier_status_counts']['unsupported']-=1
        for key in ['reachable_count_excluding_start','reachable_count_including_start','reachable_full_direct_effect_nodes']:route[key]+=1
        assert '63620' not in route['reachable_node_ids_including_start'];route['reachable_node_ids_including_start'].append('63620');route['reachable_node_ids_including_start'].sort()
    assert projected==coverage,list(differences(projected,coverage))[:8]
    paths=subprocess.check_output(['git','ls-tree','-r','--name-only',BASE,'assets','data','docs/reference'],cwd=ROOT,text=True).splitlines()
    preserved=[p for p in paths if p.endswith('.png') or p.startswith('data/')]+['docs/reference/reference.css','docs/reference/reference.js','docs/reference/art/manifest.json']
    hashes={p:sha((ROOT/p).read_bytes()) for p in preserved}
    for path,current in hashes.items():assert current==sha(oldbytes(path)),path
    old_pngs=[p for p in paths if p.endswith('.png')]
    assert sorted(old_pngs)==sorted(p.relative_to(ROOT).as_posix() for folder in [ROOT/'assets',REF] for p in folder.rglob('*.png'))
    changes=list(differences(old,data));coverage_changes=list(differences(oldcoverage,coverage))
    report={'passed':True,'baseline_commit':BASE,'reused_actual_main_fixture_count':3,'exact_compiled_casts_checked':casts,'individual_hits_checked':hits,'authoritative_html_values_and_labels_checked':len(rendered),'html_unique_ids':len(page.ids),'old_html_anchors_preserved':len(oldpage.ids),'all_anchor_and_local_file_links_valid':True,'old_default_build_and_skill_examples_preserved':True,'exact_catalog_approved_changed_paths':len(changes),'source_coverage_approved_changed_paths':len(coverage_changes),'new_complete_source_node_ids':['63620'],'new_reachable_node_ids_per_class':['63620'],'raw_source_and_chinese_mapping_files_byte_identical':True,'old_asset_pngs_preserved':len([p for p in old_pngs if p.startswith('assets/')]),'old_reference_pngs_preserved':len([p for p in old_pngs if p.startswith('docs/reference/')]),'catalog_bytes':(REF/'catalog.json').stat().st_size,'catalog_sha256':sha((REF/'catalog.json').read_bytes()),'html_sha256':sha((REF/'index.html').read_bytes()),'coverage_sha256':sha((REF/'source-tree-coverage.json').read_bytes()),'fixtures':acceptance['fixtures'],'unchanged_files':hashes,'changes':[{'kind':kind,'path':list(path),'before_sha256':digest(left),'after_sha256':digest(right)} for kind,path,left,right in changes]}
    receipt=QA/'v069-preservation.json'
    if receipt.exists():assert json.loads(receipt.read_text())==report,'Existing preservation receipt differs'
    else:
        with receipt.open('x') as f:json.dump(report,f,ensure_ascii=False,indent=2);f.write('\n')
    print(json.dumps({key:value for key,value in report.items() if key not in ['changes','unchanged_files','fixtures']},ensure_ascii=False,indent=2))
if __name__=='__main__':main()

#!/usr/bin/env python3
"""Focused v65 authoritative reference and complete v64 semantic preservation."""
from copy import deepcopy
import hashlib,json,math,subprocess
from html.parser import HTMLParser
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3];QA=Path(__file__).resolve().parent;REF=ROOT/'docs/reference';BASE='23983fe8138e591d2b1af6892b7df13a918dd19d'
LINE='Life Regeneration is applied to Energy Shield instead';ZH='生命再生改为作用于能量护盾'
GRANTS=[{'stat':'zealots_oath','value':1.0,'mode':'flat'}]
def sha(raw):return hashlib.sha256(raw).hexdigest()
def digest(value):return sha(json.dumps(value,sort_keys=True,ensure_ascii=False,separators=(',',':')).encode())
def near(a,b):assert math.isfinite(a) and abs(a-b)<=max(1e-8,abs(b)*1e-10),(a,b)
def oldbytes(path):return subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT)
def differences(a,b,path=()):
    if isinstance(a,dict) and isinstance(b,dict):
        for key in sorted(a.keys()|b.keys()):
            if key not in a:yield 'added',path+(key,),None,b[key]
            elif key not in b:yield 'removed',path+(key,),a[key],None
            else:yield from differences(a[key],b[key],path+(key,))
    elif isinstance(a,list) and isinstance(b,list) and len(a)==len(b):
        for i,(left,right) in enumerate(zip(a,b)):yield from differences(left,right,path+(i,))
    elif a!=b:yield 'changed',path,a,b
class Page(HTMLParser):
    def __init__(self):super().__init__();self.ids=[];self.links=[];self.assets=[];self.values={};self.labels={};self.active=None
    def handle_starttag(self,tag,attrs):
        attrs=dict(attrs)
        if 'id' in attrs:self.ids.append(attrs['id'])
        if 'href' in attrs:self.links.append(attrs['href'])
        if 'src' in attrs:self.assets.append(attrs['src'])
        if 'data-zealots-oath-value' in attrs:
            key=attrs['data-zealots-oath-value'];assert key not in self.values
            self.values[key]=float(attrs['data-value']);self.labels[key]='';self.active=key
    def handle_data(self,data):
        if self.active:self.labels[self.active]+=data
    def handle_endtag(self,tag):
        if tag=='strong':self.active=None
def setpath(value,path,replacement):
    for key in path[:-1]:value=value[key]
    value[path[-1]]=replacement

def main():
    old=json.loads(oldbytes('docs/reference/catalog.json'));data=json.loads((REF/'catalog.json').read_text());r=data['zealots_oath'];p=Page();html=(REF/'index.html').read_text();p.feed(html)
    assert data['game_version']=='0.65.0' and data['save_version']==r['minimum_save_version']==r['source_policy']==41 and r['equipment_vocabulary']==39
    assert r['node']['id']=='63425' and r['node']['source_lines']==[LINE]
    effect={'status':'full','grants':GRANTS,'supported':[LINE],'unsupported':[]}
    assert r['node']['execution']==effect and data['source_tree']['nodes']['63425']['execution']==effect
    assert r['node']['legacy_execution']==old['source_tree']['nodes']['63425']['execution'] and r['node']['legacy_execution']['status']=='unsupported'
    assert r['node']['name']==old['source_tree']['nodes']['63425']['name']
    assert r['raw_flat_regeneration']==10 and r['life_regeneration_fraction']==.018
    assert r['sources']['31033']['source_lines']==['Regenerate 10 Life per second','Regenerate 1.2% of Life per second']
    assert r['sources']['32482']['source_lines']==['Regenerate 0.6% of Life per second']
    for node_id,source in r['sources'].items():
        assert source['execution']==data['source_tree']['nodes'][node_id]['execution'] and source['execution']['status']=='full'
    before,after,changed=[r['examples'][key] for key in ['before','after','changed_shield']]
    assert after['allocated']==before['allocated']+['63425'] and changed['allocated']==after['allocated']
    assert before['equipment']==after['equipment']
    for slot in after['equipment']:
        if slot!='body_armour':assert after['equipment'][slot]==changed['equipment'][slot]
    assert after['equipment']['body_armour']['item']['definition_id']=='equipment:guardian_robe'
    assert after['equipment']['body_armour']['definition']['stats']==data['fixed_items']['guardian_robe']['stats']
    for base,instance in r['instances'].items():
        assert base in ['tidebound_coat','wayglass_token'] and instance['base_id']==base and instance['rarity']=='magic' and instance['item_level']==16
        assert instance['affixes']==[{'id':'lanternveil','tier':3,'value':22}]
        family=data['affixes']['lanternveil'];tier=next(t for t in family['tiers'] if t['tier']==3)
        assert instance['affixes'][0]['value']==tier['max'] and tier['level']<=16 and base in family['eligible_bases']
    assert changed['equipment']['body_armour']['item']['payload']==r['instances']['tidebound_coat']
    assert changed['equipment']['amulet']['item']['payload']==r['instances']['wayglass_token']
    rendered={'save-version':41,'source-policy':41,'vocabulary':39,'active-life-rate':0,'raw-flat':10,'raw-percent':.018,'level':19,'budget':23}
    for key,row in r['examples'].items():
        stats,profile=row['stats'],row['profile'];enabled=key!='before'
        assert row['class_id']==1 and row['level']==19 and row['whole_build_valid'] and row['save_attempts']==0
        assert row['points_spent']==len(row['allocated'])-1 and row['points_spent']+row['points_remaining']==23
        assert row['points_remaining']==(0 if enabled else 1) and len(set(row['allocated']))==len(row['allocated'])
        assert profile.keys()=={'enabled','life_rate','shield_rate'} and profile['enabled']==enabled
        assert profile['life_rate']==stats['life_regen'] and profile['shield_rate']==stats.get('shield_regeneration_rate',0)
        near(stats['life_regen_percent'],.018);near(stats['max_health'],222);near(stats['intelligence'],44)
        raw_shield=60+sum(e['definition'].get('stats',{}).get('max_shield',0) for e in row['equipment'].values())
        near(stats['max_shield'],raw_shield*(1.04+math.floor(stats['intelligence']/10)*.01))
        near(profile['life_rate'],0 if enabled else 10+.018*stats['max_health'])
        near(profile['shield_rate'],10+.018*stats['max_shield'] if enabled else 0)
        if enabled:assert stats['zealots_oath']==1 and profile['shield_rate']!=before['profile']['life_rate']
        else:assert 'zealots_oath' not in stats and 'shield_regeneration_rate' not in stats
        for label,amount in [('points',row['points_spent']),('remaining',row['points_remaining']),('max-life',stats['max_health']),('max-shield',stats['max_shield']),('life-rate',profile['life_rate']),('shield-rate',profile['shield_rate']),('recharge-rate',stats['shield_recharge_rate']),('recharge-delay',stats['shield_recharge_delay'])]:rendered[key+'-'+label]=amount
    projected=deepcopy(after['stats']);projected.pop('zealots_oath');projected.pop('shield_regeneration_rate');projected['life_regen']=before['stats']['life_regen']
    assert projected==before['stats'],'Keystone may only redirect regeneration and add its two active keys'
    near(changed['stats']['max_shield']-after['stats']['max_shield'],2.16)
    near(changed['profile']['shield_rate']-after['profile']['shield_rate'],.018*2.16)
    near(changed['stats']['shield_recharge_rate'],after['stats']['shield_recharge_rate']-2.4)
    assert all(row['stats']['shield_recharge_delay']==4 for row in r['examples'].values())
    assert p.values.keys()==rendered.keys(),(p.values.keys()-rendered.keys(),rendered.keys()-p.values.keys())
    for key,amount in rendered.items():
        near(p.values[key],amount)
        label=p.labels[key].strip();visible=float(label.rstrip('%'))/(100 if label.endswith('%') else 1)
        near(visible,amount)
    assert len(p.ids)==len(set(p.ids)) and all(key in p.ids for key in ['rules-zealots_oath','source_passives-63425'])
    for link in p.links:
        if link.startswith('#'):assert link[1:] in p.ids,link
        elif link and not link.startswith(('http:','https:','mailto:')):assert (REF/link.split('#')[0]).exists(),link
    for asset in p.assets:assert not asset.startswith(('http:','https:')) and (REF/asset).exists(),asset
    assert ZH in html and '不是已按生命计算值' in html and '潜在每秒速率' in html and '不新增连续事件规划器' in html
    assert '771→772' in r['complete_gate'] and '703→704' in r['complete_gate']
    # Project only the entire new chapter, explicit current-version fields,
    # one exact English source execution and its exact Chinese presentation.
    expected=deepcopy(old);expected['zealots_oath']=r;expected['game_version']='0.65.0'
    version_paths={('save_version',),('canonical','default_build','version'),('canonical','save_version'),('crafting','calibration_shard','save_version'),('currencies','calibration_shard','save_version'),('melee_basic','save_version'),('normal_gem_trading','schema'),('sunwell_terrace','save_version'),('town_maps','save_version')}
    for operation in ['augment','elevate','enchant','recalibrate','reforge','salvage','targeted_reforge_critical','targeted_reforge_damage','targeted_reforge_life_leech','targeted_reforge_mana_leech']:version_paths.add(('crafting',operation,'example','save_version'))
    for field in ['defense_rating_affixes','elemental_defense_affixes','elemental_resistance_caps','resolute_technique','iron_reflexes']:version_paths.add((field,'source_policy'))
    for path in version_paths:
        current=old
        for key in path:current=current[key]
        assert current==40,(path,current)
        setpath(expected,path,41)
    expected['source_tree']['nodes']['63425']['execution']=effect
    expected['source_tree_localization']['nodes']['63425']['stats']=ZH
    expected['source_tree_localization']['lines'][LINE]={'text':ZH,'status':{'grants':GRANTS,'implemented':True,'missing_consumers':[],'parser_supported':True}}
    assert expected==data,list(differences(expected,data))[:4]
    changes=list(differences(old,data))
    old_coverage=json.loads(oldbytes('docs/reference/source-tree-coverage.json'));coverage=json.loads((REF/'source-tree-coverage.json').read_text());expected_coverage=deepcopy(old_coverage)
    for row in expected_coverage['class_reachability']:
        assert row['reachable_count_excluding_start']==703
        assert sum(node['node_id']=='63425' for node in row['blocked_frontier'])==1
        row['blocked_frontier']=[node for node in row['blocked_frontier'] if node['node_id']!='63425']
        row['blocked_frontier_count']-=1;row['blocked_frontier_status_counts']['unsupported']-=1
        for field in ['reachable_count_excluding_start','reachable_count_including_start','reachable_full_direct_effect_nodes']:row[field]+=1
        row['reachable_node_ids_including_start']=sorted(row['reachable_node_ids_including_start']+['63425'])
    assert old_coverage['effect_coverage']['standard_allocation_graph']['node_api_status_counts']['full']==771
    for key in ['all_source','standard_allocation_graph']:
        group=expected_coverage['effect_coverage'][key]
        for field in ['direct_effect_entries','node_api_status_counts','node_direct_effect_status_counts']:group[field]['full']+=1;group[field]['unsupported']-=1
    node=next(row for row in expected_coverage['nodes'] if row['id']=='63425')
    node['execution'].update({'api_status':'full','coverage_status':'full','grants':GRANTS,'supported':[LINE],'unsupported':[]})
    assert expected_coverage==coverage,list(differences(expected_coverage,coverage))[:3]
    old_pngs=[p for p in subprocess.check_output(['git','ls-tree','-r','--name-only',BASE,'assets','docs/reference'],cwd=ROOT,text=True).splitlines() if p.endswith('.png')]
    assert len([p for p in old_pngs if p.startswith('assets/')])==61 and len([p for p in old_pngs if p.startswith('docs/reference/')])==68
    assert len(list((ROOT/'assets').rglob('*.png')))==61 and len(list(REF.rglob('*.png')))==68
    preservation={path:sha((ROOT/path).read_bytes()) for path in old_pngs+['docs/reference/reference.css','docs/reference/reference.js','docs/reference/art/manifest.json']}
    for path,current in preservation.items():assert current==sha(oldbytes(path)),path
    for field in ['affixes','equipment','equipment_pools','loot_profiles','current_loot_profile','current_loot_profile_id']:assert data[field]==old[field],field
    report={'passed':True,'baseline_commit':BASE,'rendered_authoritative_values_and_visible_labels_checked':len(rendered),'legal_model_states':3,'html_ids':len(p.ids),'all_anchor_and_local_asset_links_valid':True,'approved_catalog_changed_leaves':len(changes),'all_equipment_and_loot_values_unchanged':True,'coverage_only_63425_opened_for_seven_classes':True,'standard_full_nodes_before_after':[771,772],'each_class_nonstart_reachable_before_after':[703,704],'original_asset_pngs_preserved':61,'reference_pngs_preserved':68,'existing_css_js_art_manifest_byte_identical':True,'current_catalog_semantic_sha256':digest(data),'unchanged_files':preservation,'changes':[{'kind':kind,'path':list(path),'before_sha256':digest(left),'after_sha256':digest(right)} for kind,path,left,right in changes]}
    receipt=QA/'v064-preservation.json'
    if receipt.exists():assert json.loads(receipt.read_text())==report,'Existing preservation receipt differs'
    else:
        with receipt.open('x') as f:json.dump(report,f,ensure_ascii=False,indent=2);f.write('\n')
    print(json.dumps({key:value for key,value in report.items() if key not in ['changes','unchanged_files']},ensure_ascii=False,indent=2))
if __name__=='__main__':main()

#!/usr/bin/env python3
"""Focused v64 authoritative reference, links and v63 preservation checks."""
from copy import deepcopy
import hashlib,json,math,subprocess
from html.parser import HTMLParser
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3];QA=Path(__file__).resolve().parent;REF=ROOT/'docs/reference';BASE='76e2abccf533cd31c20daea92c0e05b02c0980af'
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
    def __init__(self):super().__init__();self.ids=[];self.links=[];self.assets=[];self.values={}
    def handle_starttag(self,tag,attrs):
        attrs=dict(attrs)
        if 'id' in attrs:self.ids.append(attrs['id'])
        if 'href' in attrs:self.links.append(attrs['href'])
        if 'src' in attrs:self.assets.append(attrs['src'])
        if 'data-iron-reflexes-value' in attrs:
            key=attrs['data-iron-reflexes-value'];assert key not in self.values;self.values[key]=float(attrs['data-value'])
def main():
    old=json.loads(oldbytes('docs/reference/catalog.json'));data=json.loads((REF/'catalog.json').read_text());r=data['iron_reflexes'];p=Page();html=(REF/'index.html').read_text();p.feed(html)
    assert data['game_version']=='0.64.0' and data['save_version']==r['minimum_save_version']==r['source_policy']==40 and r['equipment_vocabulary']==39
    assert r['node']['id']=='10661' and r['node']['source_lines']==['Converts all Evasion Rating to Armour. Dexterity provides no bonus to Evasion Rating']
    assert r['node']['execution']['status']=='full' and r['node']['legacy_execution']['status']=='unsupported'
    assert r['node']['execution']==data['source_tree']['nodes']['10661']['execution']
    assert r['node']['execution']['grants']==[{'stat':'iron_reflexes','value':1.0,'mode':'flat'}]
    rendered={'save-version':40,'vocabulary':39,'source-policy':40,'final-evasion':0}
    assert set(r['examples'])=={'dual_ratings','dual_ratings_hybrid','resources_hybrid'}
    for key,e in r['examples'].items():
        before,after,inputs=e['before'],e['after'],e['inputs'];a0,e0,ia,ie,h=[inputs[x] for x in ['base_armour','base_evasion','armour_increased','evasion_increased','shared_increased']]
        assert before['instance']==after['instance'] and before['stats']['accuracy']==after['stats']['accuracy']
        affixes=after['instance']['affixes'];assert len(affixes)==(4 if key=='resources_hybrid' else 6)
        assert len({a['id'] for a in affixes})==len(affixes) and sum(data['affixes'][a['id']]['kind']=='prefix' for a in affixes)<=3
        for a in affixes:
            family=data['affixes'][a['id']];tier=next(t for t in family['tiers'] if t['tier']==a['tier'])
            assert a['value']==tier['max'] and tier['level']<=after['instance']['item_level'] and after['instance']['base_id'] in family['eligible_bases']
        near(a0,0 if key=='resources_hybrid' else 120);near(e0,15 if key=='resources_hybrid' else 465)
        near(h,0 if key=='dual_ratings' else .06);near(ia,h);near(ie,h)
        near(before['stats']['armour'],a0*(1+ia));near(before['stats']['evasion'],e0*(1+ie+math.floor(before['stats']['dexterity']/5)*.01))
        near(after['profile']['armour'],a0*(1+ia)+e0*(1+ia+ie-h));near(after['profile']['converted_armour'],e0*(1+ia+ie-h))
        assert after['profile']['evasion']==0 and before['points_remaining']==1 and after['points_remaining']==0
        assert after['points_spent']==after['level']+4 and after['allocated']==before['allocated']+['10661']
        for state,row in [('before',before),('after',after)]:
            assert row['whole_build_valid'] and row['save_attempts']==0 and row['enemy_accuracy']==100
            assert row['profile']['enabled']==row['profile']['dexterity_evasion_disabled']==(state=='after')
            assert set(row['profile'])=={'enabled','dexterity_evasion_disabled','armour','evasion','converted_armour'}
            assert row['profile']['armour']==row['stats']['armour'] and row['profile']['evasion']==row['stats']['evasion']
            prefix=key+'-'+state+'-'
            for label,number in [('points',row['points_spent']),('armour',row['profile']['armour']),('evasion',row['profile']['evasion']),('converted',row['profile']['converted_armour']),('dexterity',row['stats']['dexterity']),('accuracy',row['stats']['accuracy']),('enemy-hit-chance',row['enemy_hit_chance'])]:rendered[prefix+label]=number
        assert 0<before['enemy_hit_chance']<=after['enemy_hit_chance']==1
        if key!='resources_hybrid':assert before['enemy_hit_chance']<1
        assert 'evasion_converted_to_armour' not in before['stats'] and 'iron_reflexes' not in before['stats']
        for kind in ['fire','cold','lightning']:near(before['elemental_hits'][kind]['damage_total'],after['elemental_hits'][kind]['damage_total'])
        assert before['burn']==after['burn']
        rendered.update({key+'-level':after['level'],key+'-budget':after['points_spent'],key+'-A0':a0,key+'-E0':e0})
        for field in ['armour_increased','evasion_increased','shared_increased']:rendered[key+'-'+field]=inputs[field]
    example=r['examples']['dual_ratings_hybrid']
    for state in ['before','after']:
        for amount in ['20','100','500']:rendered['physical-'+amount+'-'+state]=example[state]['physical_hits'][amount]['damage_total']
        for kind in ['fire','cold','lightning']:rendered['element-'+kind+'-'+state]=example[state]['elemental_hits'][kind]['damage_total']
        rendered['burn-'+state]=example[state]['burn']['damage_total']
    for amount in ['20','100','500']:assert example['after']['physical_hits'][amount]['damage_total']<example['before']['physical_hits'][amount]['damage_total']
    assert p.values.keys()==rendered.keys(),(p.values.keys()-rendered.keys(),rendered.keys()-p.values.keys())
    for key,value in rendered.items():near(p.values[key],value)
    assert len(p.ids)==len(set(p.ids)) and all(key in p.ids for key in ['rules-iron_reflexes','source_passives-10661'])
    for link in p.links:
        if link.startswith('#'):assert link[1:] in p.ids,link
        elif link and not link.startswith(('http:','https:','mailto:')):assert (REF/link.split('#')[0]).exists(),link
    for asset in p.assets:assert not asset.startswith(('http:','https:')) and (REF/asset).exists(),asset
    assert '同一原始词句' in html and '已经包含在最终护甲' in html
    # Precise existing-catalog preservation is checked below after enumerating
    # version metadata and the single newly executable source rule.
    changes=list(differences(old,data))
    version_paths={('save_version',),('canonical','default_build','version'),('canonical','save_version'),('crafting','calibration_shard','save_version'),('currencies','calibration_shard','save_version'),('melee_basic','save_version'),('normal_gem_trading','schema'),('sunwell_terrace','save_version'),('town_maps','save_version')}
    for operation in ['augment','elevate','enchant','recalibrate','reforge','salvage','targeted_reforge_critical','targeted_reforge_damage','targeted_reforge_life_leech','targeted_reforge_mana_leech']:version_paths.add(('crafting',operation,'example','save_version'))
    for kind,path,left,right in changes:
        if path==('iron_reflexes',):assert kind=='added'
        elif path==('game_version',):assert left=='0.63.0' and right=='0.64.0'
        elif path in version_paths:assert left==39 and right==40
        elif path in [('defense_rating_affixes','source_policy'),('elemental_defense_affixes','source_policy'),('elemental_resistance_caps','source_policy'),('resolute_technique','source_policy')]:assert left==38 and right==40
        elif path[:3]==('source_tree','nodes','10661'):assert path[3]=='execution'
        elif path==('source_tree_localization','nodes','10661','stats'):pass
        elif path[:2]==('source_tree_localization','lines') and 'Converts all Evasion Rating' in str(path[2]):pass
        else:raise AssertionError(('Unexpected existing catalog change',kind,path,left,right))
    old_coverage=json.loads(oldbytes('docs/reference/source-tree-coverage.json'));coverage=json.loads((REF/'source-tree-coverage.json').read_text())
    expected_coverage=deepcopy(old_coverage)
    for row in expected_coverage['class_reachability']:
        row['blocked_frontier']=[node for node in row['blocked_frontier'] if node['node_id']!='10661']
        row['blocked_frontier_count']-=1;row['blocked_frontier_status_counts']['unsupported']-=1
        for field in ['reachable_count_excluding_start','reachable_count_including_start','reachable_full_direct_effect_nodes']:row[field]+=1
        row['reachable_node_ids_including_start']=sorted(row['reachable_node_ids_including_start']+['10661'])
    for key in ['all_source','standard_allocation_graph']:
        group=expected_coverage['effect_coverage'][key]
        for field in ['direct_effect_entries','node_api_status_counts','node_direct_effect_status_counts']:
            group[field]['full']+=1;group[field]['unsupported']-=1
    node=next(row for row in expected_coverage['nodes'] if row['id']=='10661')
    node['execution'].update({'api_status':'full','coverage_status':'full','grants':r['node']['execution']['grants'],'supported':r['node']['source_lines'],'unsupported':[]})
    assert expected_coverage==coverage,list(differences(expected_coverage,coverage))[:3]
    old_pngs=[p for p in subprocess.check_output(['git','ls-tree','-r','--name-only',BASE,'assets','docs/reference'],cwd=ROOT,text=True).splitlines() if p.endswith('.png')]
    assert len([p for p in old_pngs if p.startswith('assets/')])==61 and len([p for p in old_pngs if p.startswith('docs/reference/')])==68
    preservation={path:sha((ROOT/path).read_bytes()) for path in old_pngs+['docs/reference/reference.css','docs/reference/reference.js','docs/reference/art/manifest.json']}
    for path,current in preservation.items():assert current==sha(oldbytes(path)),path
    for field in ['affixes','equipment','equipment_pools','loot_profiles','current_loot_profile','current_loot_profile_id']:assert data[field]==old[field],field
    report={'passed':True,'baseline_commit':BASE,'rendered_authoritative_values_checked':len(rendered),'legal_model_states':6,'html_ids':len(p.ids),'all_anchor_and_local_asset_links_valid':True,'approved_catalog_changed_leaves':len(changes),'all_equipment_and_loot_values_unchanged':True,'coverage_only_10661_opened_for_seven_classes':True,'original_asset_pngs_preserved':61,'reference_pngs_preserved':68,'existing_css_js_art_manifest_byte_identical':True,'current_catalog_semantic_sha256':digest(data),'unchanged_files':preservation,'changes':[{'kind':kind,'path':list(path),'before_sha256':digest(left),'after_sha256':digest(right)} for kind,path,left,right in changes]}
    receipt=QA/'v063-preservation.json'
    if receipt.exists():assert json.loads(receipt.read_text())==report,'Existing preservation receipt differs'
    else:
        with receipt.open('x') as f:json.dump(report,f,ensure_ascii=False,indent=2);f.write('\n')
    print(json.dumps({key:value for key,value in report.items() if key not in ['changes','unchanged_files']},ensure_ascii=False,indent=2))
if __name__=='__main__':main()

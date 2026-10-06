#!/usr/bin/env python3
"""Focused v62 same-source values, current-pool projection, links and assets."""
from copy import deepcopy
import hashlib
from html.parser import HTMLParser
import importlib.util
import json
import math
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[3]
QA=ROOT/'docs/qa/v062-reference';REF=ROOT/'docs/reference'
BASE='d884caea7a2260f4535ba4da2d7e005e6df006d4'
NEW=['ironhide','mistweave']
def decode(raw):return json.loads(raw,parse_int=float,parse_float=float)
def sha(raw):return hashlib.sha256(raw).hexdigest()
def digest(value):return sha(json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode())
def near(a,b):assert math.isfinite(a) and abs(a-b)<max(1e-9,abs(b)*1e-12),(a,b)
def save(name,data):(QA/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
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
    def __init__(self):super().__init__();self.ids=[];self.links=[];self.assets=[];self.values={};self.elemental={}
    def handle_starttag(self,tag,attrs):
        attrs=dict(attrs)
        if 'id' in attrs:self.ids.append(attrs['id'])
        if 'href' in attrs:self.links.append(attrs['href'])
        if 'src' in attrs:self.assets.append(attrs['src'])
        for field,target in [('data-defense-rating-value',self.values),('data-elemental-affix-value',self.elemental)]:
            if field in attrs:
                assert attrs[field] not in target;target[attrs[field]]=float(attrs['data-value'])

def main():
    old=decode(subprocess.check_output(['git','show',BASE+':docs/reference/catalog.json'],cwd=ROOT));data=decode((REF/'catalog.json').read_bytes())
    r=data['defense_rating_affixes'];page=Page();html=(REF/'index.html').read_text();page.feed(html)
    assert data['game_version']=='0.62.0' and data['save_version']==r['minimum_save_version']==r['vocabulary']==39 and r['source_policy']==38
    assert r['pool_id']=='defense_v39' and r['loot_profile_id']=='canonical_v39' and r['prefix_families']==['rootwell','deepwell','lanternveil']+NEW
    assert r['pool']==data['equipment_pools']['defense_v39'] and r['loot_profile']==data['current_loot_profile']
    assert r['pool']['affix_ids']==old['equipment_pools']['defense_v37']['affix_ids']+NEW
    rendered={'save-version':39,'vocabulary':39,'source-policy':38}
    ranges={'ironhide':[(30,50),(55,80),(85,120)],'mistweave':[(200,260),(270,350),(360,450)]}
    for key in NEW:
        family=r['new_families'][key];published=data['affixes'][key]
        assert family['kind']=='prefix' and family['unit']=='flat' and family['scope']=='equipped_character'
        assert family['allowed_base_ids']==published['eligible_bases']==['emberhide_vest'] and published['pools']==['defense_v39']
        assert family['group']==family['stat']+'_rating' and not published['affected_skills']
        for index,tier in enumerate(family['tiers']):
            assert tier=={'tier':index+1,'level':[1,8,16][index],'weight':[100,60,30][index],'min':ranges[key][index][0],'max':ranges[key][index][1]}
            stem=key+'-'+str(index+1)
            rendered.update({stem+'-'+field:tier[field] for field in ['tier','level','min','max','weight']})
            for limit in ['min','max']:assert published['formatted_ranges'][index][limit]=='+'+str(int(tier[limit]))
        assert family['stat'] in ['armour','evasion']
    for level,available in r['tier_boundaries'].items():
        expect=[i for i,minimum in [(1,1),(2,8),(3,16)] if minimum<=int(level)]
        assert available=={key:expect for key in NEW}
    for key,example in r['examples'].items():
        assert example['class_id']==0 and example['whole_build_valid'] and example['save_attempts']==0
        item=example['definition']['stats'];stats=example['stats'];affixes=example['instance']['affixes']
        if key=='white_base':assert not affixes and example['instance']['rarity']=='normal'
        else:
            assert [row['id'] for row in affixes]==NEW+[key,'emberward','rimeward','stormward']
            assert all(row['tier']==3 for row in affixes) and example['instance']['rarity']=='rare'
            assert item['armour']==stats['armour']==120 and item['evasion']==450
            near(stats['evasion'],483.6)
            for field,family,extra in [('max_health','rootwell',32),('max_mana','deepwell',22),('max_shield','lanternveil',22)]:
                assert item.get(field,0)==(8 if field=='max_health' else 0)+(extra if key==family else 0)
        rendered.update({key+'-item-'+field:item.get(field,0) for field in ['armour','evasion','max_health','max_mana','max_shield']})
        rendered.update({key+'-final-'+field:stats[field] for field in ['armour','evasion']})
    budget=decode((ROOT/'docs/qa/v062-budget/budget.json').read_bytes())
    assert len(r['evasion_rows'])==42
    for row in r['evasion_rows']:
        reference=next(entry for entry in budget['evasion_rows'] if entry['class_id']==row['class_id'] and entry['flat_item_evasion']==row['flat_item_evasion'])
        for field in ['base_dexterity','effective_evasion','enemy_accuracy','hit_chance']:near(row[field],reference[field])
        assert row['baseline_hit_chance']==1 and 0<row['hit_chance']<1 and row['whole_build_valid'] and row['save_attempts']==0
        if (row['tier'],row['bound']) in [(1,'min'),(3,'max')]:
            stem='evasion-'+str(int(row['class_id']))+'-'+str(int(row['tier']))+'-'+row['bound']
            for name,field in [('dexterity','base_dexterity'),('flat','flat_item_evasion'),('effective','effective_evasion'),('accuracy','enemy_accuracy'),('before','baseline_hit_chance'),('after','hit_chance')]:rendered[stem+'-'+name]=row[field]
    assert len(r['catalog_attacks'])==4
    for index,row in enumerate(r['catalog_attacks']):
        reference=next(entry for entry in budget['armour_rows'] if entry['map']==row['map_id'] and entry['tier']==row['tier'] and entry['species']==row['species'] and entry['rarity']==('normal' if index==0 else 'boss') and entry['damage_modifier']==row['damage_modifier'])
        assert row['components']==reference['components'] and row['armour']==120 and row['accuracy']==100
        near(row['before']['damage_total'],reference['before_armour']);near(row['after']['damage_total'],reference['armour_rows'][-1]['damage'])
        assert row['after']['damage_total']<row['before']['damage_total']
        rendered.update({'attack-'+str(index)+'-armour':row['armour'],'attack-'+str(index)+'-before':row['before']['damage_total'],'attack-'+str(index)+'-after':row['after']['damage_total']})
    for key,case in r['scope_hits'].items():
        assert case['before']['damage_total']==100
        if key!='physical':assert case['after']['damage_total']==100
        else:assert case['after']['damage_total']<100
        for state in ['before','after']:rendered['scope-'+key+'-'+state]=case[state]['damage_total']
    rendered['burn-damage']=r['burn_example']['damage_total'];assert rendered['burn-damage']==100
    assert page.values.keys()==rendered.keys(),(page.values.keys()-rendered.keys(),rendered.keys()-page.values.keys())
    for key,number in rendered.items():near(page.values[key],number)
    assert page.elemental['vocabulary']==39 and page.elemental['reforge-vocabulary']==37
    assert len(page.ids)==len(set(page.ids)) and all(key in page.ids for key in ['rules-defense_rating_affixes','affixes-ironhide','affixes-mistweave'])
    for target in page.links:
        if target.startswith('#'):assert target[1:] in page.ids,target
        elif target and not target.startswith(('https://','http://','mailto:')):assert (REF/target.split('#')[0]).exists(),target
    for asset in page.assets:assert not asset.startswith(('https:','http:')) and (REF/asset).exists(),asset
    assert '五个前缀族争三个名额' in html and '历史v37普通重铸见证' in html
    # Complete old-catalog projection: only precise current metadata/new material
    # and the existing Main current-pool reward witness are accepted.
    expected=deepcopy(old)
    expected['game_version']='0.62.0';expected['defense_rating_affixes']=r
    for key in NEW:expected['affixes'][key]=data['affixes'][key]
    for key in old['equipment_pools']['defense_v37']['affix_ids']:expected['affixes'][key]['pools'].append('defense_v39')
    expected['equipment']['emberhide_vest']['eligible_affixes']+=NEW
    expected['equipment_pools']['defense_v39']=deepcopy(old['equipment_pools']['defense_v37']);expected['equipment_pools']['defense_v39']['affix_ids']+=NEW;expected['equipment_pools']['defense_v39']['min_save_version']=39
    profile=deepcopy(old['current_loot_profile']);profile[2]['pool_id']='defense_v39'
    expected['loot_profiles']['canonical_v39']=profile
    for target in [expected,expected['forgeblade']]:target['current_loot_profile']=profile;target['current_loot_profile_id']='canonical_v39'
    version_paths=[('save_version',),('canonical','default_build','version'),('canonical','save_version'),('crafting','calibration_shard','save_version'),('currencies','calibration_shard','save_version'),('melee_basic','save_version'),('normal_gem_trading','schema'),('sunwell_terrace','save_version'),('town_maps','save_version')]
    for operation in ['augment','elevate','enchant','recalibrate','reforge','salvage','targeted_reforge_critical','targeted_reforge_damage','targeted_reforge_life_leech','targeted_reforge_mana_leech']:version_paths.append(('crafting',operation,'example','save_version'))
    for path in version_paths:
        target=expected
        for part in path[:-1]:target=target[part]
        assert target[path[-1]]==38;target[path[-1]]=39
    craft=expected['crafting']['calibration_shard']['rules'];craft['affix_ids']+=NEW;craft['catalog_vocabulary']=39;craft['eligible_families_by_base']['emberhide_vest']+=NEW
    for operation in ['targeted_reforge_critical','targeted_reforge_damage','targeted_reforge_life_leech','targeted_reforge_mana_leech']:expected['crafting'][operation]['catalog_vocabulary']=39
    expected['resolute_technique']['equipment_vocabulary']=39
    elemental=expected['elemental_defense_affixes'];elemental.update({'authored_pool_id':'defense_v37','authored_vocabulary':37,'reforge_vocabulary':37,'vocabulary':39,'pool_id':'defense_v39','pool':expected['equipment_pools']['defense_v39'],'loot_profile_id':'canonical_v39','loot_profile':profile})
    # These are current-entry samples, explicitly not frozen historical seeds.
    for map_id in ['old_garden','broken_ruins','sunwell_terrace']:
        affixes=elemental['formal_map_tier_iii'][map_id]['sample']['affixes']
        affixes[0].update({'id':'ironhide','value':61 if map_id=='old_garden' else 31})
        if map_id!='old_garden':affixes[1].update({'id':'lanternveil','value':13});affixes[2].update({'id':'mistweave','value':347})
    assert expected==data,list(differences(expected,data))[:8]
    changes=list(differences(old,data))
    projection=deepcopy(data)
    for kind,path,left,right in changes:
        target=projection
        for part in path[:-1]:target=target[part]
        if kind=='added':del target[path[-1]]
        else:target[path[-1]]=left
    assert projection==old
    coverage=(REF/'source-tree-coverage.json').read_bytes();baseline=json.loads((QA/'v061-baseline.json').read_text())
    assert sha(coverage)==baseline['source_coverage_sha256']
    for group,count in [('asset_pngs',61),('reference_pngs',68)]:assert len(baseline[group])==count and all(sha((ROOT/path).read_bytes())==value for path,value in baseline[group].items())
    report={'passed':True,'baseline_commit':BASE,'rendered_authoritative_values_checked':len(rendered),'actual_class_rating_rows':42,'actual_catalog_attack_rows':4,'legal_item_tradeoff_examples':4,'html_ids':len(page.ids),'all_html_anchor_and_local_asset_links_valid':True,'approved_catalog_changed_leaves':len(changes),'old_catalog_semantic_sha256':digest(old),'projected_catalog_semantic_sha256':digest(projection),'current_catalog_semantic_sha256':digest(data),'source_coverage_byte_identical':True,'source_execution_localization_unchanged':data['source_tree']==old['source_tree'] and data['source_tree_localization']==old['source_tree_localization'],'historical_explicit_pools_and_profiles_preserved':all(data['equipment_pools'][key]==value for key,value in old['equipment_pools'].items()) and all(data['loot_profiles'][key]==value for key,value in old['loot_profiles'].items()),'historical_six_affix_budget_and_reforge_witness_preserved':data['elemental_defense_affixes']['examples']==old['elemental_defense_affixes']['examples'] and data['elemental_defense_affixes']['ordinary_reforge_witness']==old['elemental_defense_affixes']['ordinary_reforge_witness'],'current_default_reward_samples_intentionally_changed':True,'old_asset_pngs_unchanged':61,'old_reference_pngs_unchanged':68,'changes':[{'kind':kind,'path':list(path),'before_sha256':digest(left),'after_sha256':digest(right)} for kind,path,left,right in changes]}
    assert all(report[key] for key in ['source_execution_localization_unchanged','historical_explicit_pools_and_profiles_preserved','historical_six_affix_budget_and_reforge_witness_preserved'])
    save('v061-projection-preservation.json',report);print(json.dumps({key:value for key,value in report.items() if key!='changes'},ensure_ascii=False,indent=2))
if __name__=='__main__':main()

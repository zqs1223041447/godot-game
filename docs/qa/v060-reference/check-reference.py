#!/usr/bin/env python3
"""v60 actual projections, rendered numbers, exact v59 bounded preservation."""
from copy import deepcopy
import hashlib
from html.parser import HTMLParser
import json
import math
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[3]
QA=ROOT/'docs/qa/v060-reference'
REF=ROOT/'docs/reference'
BASE='0816322e4c9a53d264bce9c5223810a93ead2348'
NEW=['rimeward','stormward']
ELEMENTS=['fire','cold','lightning']
def decode(raw):return json.loads(raw,parse_int=float,parse_float=float)
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def digest(value):return hashlib.sha256(json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def near(a,b):assert math.isfinite(a) and abs(a-b)<1e-9,(a,b)
def save(name,value):
    with (QA/name).open('x') as stream:json.dump(value,stream,ensure_ascii=False,indent=2);stream.write('\n')
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
    def __init__(self):super().__init__();self.ids=[];self.links=[];self.assets=[];self.values={};self.article=None;self.text=[]
    def handle_starttag(self,tag,attrs):
        attrs=dict(attrs)
        if 'id' in attrs:self.ids.append(attrs['id'])
        if tag=='article':self.article=attrs.get('id')
        if tag=='a':self.links.append(attrs.get('href',''))
        if tag in ['img','link','script']:
            asset=attrs.get('src',attrs.get('href',''))
            if asset:self.assets.append(asset)
        if 'data-elemental-affix-value' in attrs:
            assert self.article=='rules-elemental_defense_affixes'
            key=attrs['data-elemental-affix-value'];assert key not in self.values
            self.values[key]=float(attrs['data-value'])
    def handle_endtag(self,tag):
        if tag=='article':self.article=None
    def handle_data(self,data):self.text.append(data)
def main():
    old=decode(subprocess.check_output(['git','show',BASE+':docs/reference/catalog.json'],cwd=ROOT))
    data=decode((REF/'catalog.json').read_bytes());s=data['elemental_defense_affixes'];page=Page();page.feed((REF/'index.html').read_text())
    assert data['game_version']=='0.60.0' and data['save_version']==s['minimum_save_version']==s['vocabulary']==37
    assert s['source_policy']==36 and s['slot_targets']==['body_armour']
    assert s['pool_id']=='defense_v37' and s['loot_profile_id']=='canonical_v37'
    assert s['pool']['affix_ids']==old['equipment_pools']['defense']['affix_ids']+NEW
    assert s['pool']['base_ids']==['emberhide_vest'] and s['pool']['min_save_version']==37
    expected_profile=deepcopy(old['loot_profiles']['canonical_v34']);expected_profile[2]['pool_id']='defense_v37'
    assert data['current_loot_profile']==s['loot_profile']==expected_profile
    rendered={'vocabulary':37,'save-version':37,'source-policy':36,'body-slots':1}
    for family_id,stat,label in [('rimeward','cold_resistance','冰霜抗性'),('stormward','lightning_resistance','闪电抗性')]:
        family=s['new_families'][family_id];catalog=data['affixes'][family_id]
        assert family['stat']==family['group']==stat and family['kind']=='suffix' and family['unit']=='percent'
        assert family['label']==label and family['allowed_base_ids']==catalog['eligible_bases']==['emberhide_vest']
        assert catalog['pools']==['defense_v37']
        for index,(level,low,high,weight) in enumerate([(1,8,12,100),(8,13,18,60),(16,19,25,30)],1):
            tier=family['tiers'][index-1];assert tier=={'tier':index,'level':level,'min':low,'max':high,'weight':weight}
            assert catalog['formatted_ranges'][index-1]=={'min':f'+{low}%','max':f'+{high}%'}
            assert label+' +'+str(high)+'%' in catalog['formatted_examples'][index-1]
            stem=family_id+'-'+str(index);rendered.update({stem+'-tier':index,stem+'-level':level,stem+'-weight':weight})
    for level,tiers in [(1,[1]),(7,[1]),(8,[1,2]),(15,[1,2]),(16,[1,2,3]),(30,[1,2,3])]:
        assert s['tier_boundaries'][str(level)]=={key:tiers for key in NEW}
    for key,raw,health,mana,shield,recovery in [('white_base',[.15,0,0],8,0,0,0),('six_max',[.4,.25,.25],40,22,22,0),('mana_recovery',[.15,.25,.25],40,22,22,.14)]:
        ex=s['examples'][key];p=ex['profile'];item=ex['definition']['stats'];assert ex['whole_build_valid'] and ex['save_attempts']==0 and p['ok']
        for field,target in [('max_health',health),('max_mana',mana),('max_shield',shield),('mana_regen_increased',recovery)]:near(item.get(field,0),target)
        rendered.update({key+'-health':health,key+'-mana':mana,key+'-shield':shield,key+'-mana-regen':recovery})
        for element,amount in zip(ELEMENTS,raw):
            near(p['raw_resistances'][element],amount);near(p['effective_resistances'][element],amount);near(p['maximum_resistances'][element],.75)
            near(ex['hits'][element]['damage_total'],100*(1-amount));rendered[key+'-'+element+'-raw']=amount
        assert ex['instance']['base_id']=='emberhide_vest'
    full=s['examples']['six_max'];assert [(a['id'],a['tier'],a['value']) for a in full['instance']['affixes']]==[(key,3,value) for key,value in [('rootwell',32),('deepwell',22),('lanternveil',22),('emberward',25),('rimeward',25),('stormward',25)]]
    for element in ELEMENTS:rendered['six-max-'+element+'-hit']=full['hits'][element]['damage_total']
    for key,expected in [('default_75',[.35,.5,.5]),('safety_83',[.43,.58,.58])]:
        for element,amount in zip(ELEMENTS,expected):near(full['additional_raw_required'][key][element],amount);rendered[key+'-'+element+'-gap']=amount
    for map_id,level,tiers in [('old_garden',15,[1,2]),('broken_ruins',17,[1,2,3]),('sunwell_terrace',19,[1,2,3])]:
        ex=s['formal_map_tier_iii'][map_id];assert ex['item_level']==ex['sample']['item_level']==level and ex['eligible_tiers']==tiers and ex['save_attempts']==0
        rendered[map_id+'-ilvl']=level
    white=s['test_supply']['instance']['payload'];assert white['rarity']=='normal' and white['affixes']==[] and white['base_id']=='emberhide_vest'
    assert all(a['kind']=='suffix' for a in s['damage_target_families']) and {a['id'] for a in s['damage_target_families']}=={'coalglow','rimeecho','sparkthread'}
    witness=s['ordinary_reforge_witness'];assert witness['plan']['ok'] and {'emberward',*NEW}<={a['id'] for a in witness['plan']['instance']['affixes']}
    rendered['reforge-seed']=witness['seed']
    assert page.values.keys()==rendered.keys(),(page.values.keys()-rendered.keys(),rendered.keys()-page.values.keys())
    for key,value in rendered.items():near(page.values[key],value)
    caps=data['elemental_resistance_caps'];assert caps['equipment']['equipment_cold_sources']==['rimeward'] and caps['equipment']['equipment_lightning_sources']==['stormward']
    text=''.join(page.text)
    for stale in ['现装备和珠宝不供给原始冰、电抗','当前可获得的防御属性仅有火焰抗性']:assert stale not in text
    assert len(page.ids)==len(set(page.ids))
    for target in page.links:
        if target.startswith('#'):assert target[1:] in page.ids,target
        elif target and not target.startswith(('https://','http://','mailto:')):assert (REF/target.split('#')[0]).exists(),target
    for asset in page.assets:assert not asset.startswith(('http:','https:')) and (REF/asset).exists(),asset
    # Only these exact metadata additions, append-only lists, and version values
    # can be projected away. Every other legacy observation must match v59.
    approved=[];projection=deepcopy(data)
    for kind,path,before,after in differences(old,data):
        category=None
        if kind=='added' and path in [('elemental_defense_affixes',),('affixes','rimeward'),('affixes','stormward'),('equipment_pools','defense_v37'),('loot_profiles','canonical_v37')]:category='new_v37_projection'
        elif path[:1]==('affixes',) and len(path)==3 and path[-1]=='pools' and path[1] in old['equipment_pools']['defense']['affix_ids'] and after==before+['defense_v37']:category='appended_pool_membership'
        elif path in [('equipment','emberhide_vest','eligible_affixes'),('crafting','calibration_shard','rules','affix_ids'),('crafting','calibration_shard','rules','eligible_families_by_base','emberhide_vest')] and after==before+NEW:category='appended_v37_families'
        elif path in [('current_loot_profile',2,'pool_id'),('forgeblade','current_loot_profile',2,'pool_id')] and before=='defense' and after=='defense_v37':category='current_defense_lane'
        elif path in [('current_loot_profile_id',),('forgeblade','current_loot_profile_id')] and before=='canonical_v34' and after=='canonical_v37':category='current_profile_name'
        elif path==('elemental_resistance_caps','equipment','equipment_cold_sources') and before==[] and after==['rimeward']:category='current_cold_supply'
        elif path==('elemental_resistance_caps','equipment','equipment_lightning_sources') and before==[] and after==['stormward']:category='current_lightning_supply'
        elif path[-1] in ['version','save_version','schema'] and before==36 and after==37:category='schema_version'
        elif path[-1]=='catalog_vocabulary' and path[0]=='crafting' and before==34 and after==37:category='current_crafting_vocabulary'
        elif path==('game_version',) and before=='0.59.0' and after=='0.60.0':category='game_version'
        assert category is not None,(kind,path,before,after)
        at=projection
        for part in path[:-1]:at=at[part]
        if kind=='added':del at[path[-1]]
        else:at[path[-1]]=before
        approved.append({'kind':kind,'path':list(path),'category':category,'before':before,'after_sha256':digest(after)})
    assert projection==old and digest(projection)==digest(old)
    baseline=json.loads((QA/'v059-baseline.json').read_text())
    for group,count in [('asset_pngs',61),('reference_pngs',68),('font',2)]:
        assert len(baseline[group])==count and {p:sha(ROOT/p) for p in baseline[group]}==baseline[group]
    assert sha(REF/'source-tree-coverage.json')==baseline['source_coverage_sha256']
    font=json.loads((QA/'font-coverage.stdout.log.txt').read_text());assert font['ok'] and not font['missing'] and not font['lost_baseline'] and not font['empty_han'] and not font['errors']
    report={'passed':True,'baseline_commit':BASE,'numeric_decode':'Both catalogs parse_int=float and parse_float=float; canonical object keys',
            'old_catalog_semantic_sha256':digest(old),'current_catalog_semantic_sha256':digest(data),'projected_catalog_semantic_sha256':digest(projection),
            'approved_changed_leaves':len(approved),'rendered_authoritative_values_checked':len(rendered),'html_ids':len(page.ids),'all_html_anchor_and_local_asset_links_valid':True,
            'old_asset_pngs_unchanged':61,'old_reference_pngs_unchanged':68,'font_and_manifest_unchanged':True,'source_coverage_bytes_unchanged':True,
            'font_report':font,'ordinary_reforge_seed':witness['seed'],'approved_changes':approved}
    save('v059-projection-preservation.json',report)
    print(json.dumps({k:v for k,v in report.items() if k!='approved_changes'},ensure_ascii=False,indent=2))
if __name__=='__main__':main()

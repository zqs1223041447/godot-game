#!/usr/bin/env python3
"""Focused v76 provenance, real values, deterministic artifact and v75 preservation checks."""
from copy import deepcopy
import hashlib,json,math,subprocess
from html.parser import HTMLParser
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3];QA=Path(__file__).resolve().parent;REF=ROOT/'docs/reference'
def sha(raw):return hashlib.sha256(raw).hexdigest()
def digest(value):return sha(json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode())
def near(a,b):assert math.isfinite(a) and abs(a-b)<=max(1e-9,abs(b)*1e-10),(a,b)
class Page(HTMLParser):
    def __init__(self):super().__init__();self.ids=[];self.links=[];self.assets=[];self.values={};self.labels={};self.active=None;self.cards={};self.card=None;self.depth=0
    def handle_starttag(self,tag,attrs):
        attrs=dict(attrs)
        if 'id' in attrs:self.ids.append(attrs['id'])
        if 'href' in attrs:self.links.append(attrs['href'])
        if 'src' in attrs:self.assets.append(attrs['src'])
        if tag=='article':self.card=attrs.get('id');self.cards[self.card]=''
        if 'data-source-shield-value' in attrs:
            key=attrs['data-source-shield-value'];assert key not in self.values
            self.values[key]=float(attrs['data-value']);self.labels[key]='';self.active=key
    def handle_data(self,text):
        if self.active:self.labels[self.active]+=text
        if self.card:self.cards[self.card]+=text
    def handle_endtag(self,tag):
        if tag=='strong':self.active=None
        if tag=='article':self.card=None

def main():
    baseline=json.loads((QA/'v075-baseline.json').read_text());data=json.loads((REF/'catalog.json').read_text());rule=data['source_monster_shield_recharge']
    assert data['game_version']=='0.76.0' and data['save_version']==rule['save_version']==47
    assert rule['equipment_vocabulary']==46 and rule['source_policy']==45
    assert set(data)==set(baseline['top_level_sha256'])|{'source_monster_shield_recharge'}
    preserved=[]
    for key,expected in baseline['top_level_sha256'].items():
        if key not in ['game_version','mechanisms','source_monster_movement','source_monster_damage_life']:
            assert digest(data[key])==expected,key;preserved.append(key)
    common={'current_definition_count','current_pool','current_roll_policy'}
    for chapter,baseline_key,extra in [('source_monster_movement','movement_fields_sha256',set()),('source_monster_damage_life','damage_life_fields_sha256',{'current_source_definition_count','cache','sampler'})]:
        for key,expected in baseline[baseline_key].items():
            if key not in common|extra:assert digest(data[chapter][key])==expected,chapter+'.'+key
        assert set(data[chapter])-set(baseline[baseline_key])=={'damage_life_pool','damage_life_roll_policy'}
    assert len(baseline['mechanisms'])==26 and len(data['mechanisms'])==28
    assert rule['legacy_definition_count']==23 and rule['current_source_definition_count']==5 and rule['current_definition_count']==28
    for key,old in baseline['mechanisms'].items():assert digest(data['mechanisms'][key])==digest(old),key
    new_ids={'source_aegis_capacity','source_aegis_recovery'};assert set(data['mechanisms'])-set(baseline['mechanisms'])==new_ids
    assert set(rule['bindings'])==new_ids
    expected_bindings={'source_aegis_capacity':[('58218',0,'8% increased maximum Energy Shield','max_shield',.08)],'source_aegis_recovery':[('21929',1,'4% increased maximum Energy Shield','max_shield',.04),('6949',1,'10% increased Energy Shield Recharge Rate','shield_recharge_rate_increased',.10)]}
    rendered={'current-count':(28,False),'legacy-count':(23,False),'source-count':(5,False),'save-version':(47,False),'vocabulary':(46,False),'source-policy':(45,False)}
    for key,expected in expected_bindings.items():
        binding=rule['bindings'][key];definition=binding['definition'];entries=binding['source_entries'];effects=binding['source_effects'];tree=data['source_tree'];grants=[]
        assert len(entries)==len(effects)==len(expected)
        for index,((node,line_index,line,stat,amount),entry,effect) in enumerate(zip(expected,entries,effects)):
            assert entry['node_id']==node and entry['stat_index']==line_index and entry['raw_line']==line
            assert tree['nodes'][node]['stats'][line_index]==line
            for a,b in [('source_hash','source_sha256'),('source_version','source_version'),('source_commit','source_commit')]:assert entry[a]==tree[b]
            assert entry['source_url']=='https://raw.githubusercontent.com/grindinggear/skilltree-export/'+tree['source_commit']+'/data.json'
            assert effect['supported'] and effect['grants']==[{'stat':stat,'mode':'increased','value':amount}]
            grants+=effect['grants'];rendered[key+'-grant-'+str(index)]=(amount,True)
        assert definition['source_refs']==entries and definition['source_entry']==entries[0]
        assert definition['source_line']=='\n'.join(e['raw_line'] for e in entries)
        assert definition['typed_grants']==grants and definition['source_policy']==definition['source_save_version']==45
        stats={'shield_recharge_rate_increased':.1} if key.endswith('recovery') else {}
        capacity={'max_shield':.04 if key.endswith('recovery') else .08}
        assert definition['stats']==stats and definition['capacity_increased']==capacity
        if key.endswith('recovery'):assert definition['source_entries']==entries and definition['source_entry_scope']=='first_entry_only'
        for actor in ['player','monster']:
            grant=binding[actor+'_grant'];assert grant['ok'] and not grant['errors'] and grant['actor']==actor
            assert grant['role_coefficient']==1 and grant['stats']==stats and grant['capacity_increased']==capacity
            assert grant['source_grants']==[definition] and grant['mechanism_ids']==[key]
            assert not {'max_shield','shield_regen','shield_recharge_start_faster'}&set(grant['stats'])
        mechanism=data['mechanisms'][key]
        for k,v in definition.items():assert mechanism[k]==v,(key,k)
        assert mechanism['supported_actors']==['player','monster']
        assert binding['legacy_grant']['stats']==baseline['mechanisms'][binding['legacy_id']]['stats']
        rendered[key+'-coefficient']=(1,False)
    legacy=['ember_power','gale_stride','grove_vitality','aegis_capacity','aegis_recovery'];stride=legacy.copy();stride[1]='source_gale_stride';damage_life=stride.copy();damage_life[0]='source_ember_power';damage_life[2]='source_grove_vitality';current=damage_life[:3]+['source_aegis_capacity','source_aegis_recovery']
    for chapter in [rule,data['source_monster_movement'],data['source_monster_damage_life']]:
        assert chapter['legacy_pool']==legacy and chapter['stride_pool']==stride and chapter['damage_life_pool']==damage_life and chapter['current_pool']==current
        assert chapter['legacy_roll_policy']=='legacy_flat_v1' and chapter['stride_roll_policy']=='source_stride_v1' and chapter['damage_life_roll_policy']=='source_damage_life_v2' and chapter['current_roll_policy']=='source_shield_v3'
        assert chapter['current_definition_count']==28
    assert rule['budget_policy']=='monster-shield-supply-v1'
    assert rule['supplies']=={'source_aegis_capacity':{'max_shield':3.12,'shield_regen':0.0},'source_aegis_recovery':{'max_shield':1.56,'shield_regen':.4225}}
    for key,supply in rule['supplies'].items():rendered[key+'-base-shield']=(supply['max_shield'],False);rendered[key+'-base-rate']=(supply['shield_regen'],False)
    assert [(r['wave'],r['template_id'],r['rarity']) for r in rule['budget']]==[(2,'crawler','rare'),(10,'brute','rare')]
    expected_variants={'base':([],0,0,0,0),'legacy_capacity':(['aegis_capacity'],3.12,0,0,0),'legacy_recovery':(['aegis_recovery'],1.56,.4225,.4225,0),'legacy_pair':(['aegis_capacity','aegis_recovery'],4.68,.4225,.4225,0),'current_capacity':(['source_aegis_capacity'],3.3696,0,0,.08),'current_recovery':(['source_aegis_recovery'],1.6224,.4225,.46475,.04),'current_pair':(['source_aegis_capacity','source_aegis_recovery'],5.2416,.4225,.46475,.12)}
    count=0
    for row in rule['budget']:
        prefix=str(row['wave'])+'-'+row['template_id'];examples=row['examples'];assert set(examples)==set(expected_variants)
        hp=110.2 if row['template_id']=='crawler' else 579.5;rendered[prefix+'-life']=(hp,False)
        for key,(ids,shield,base_rate,rate,increase) in expected_variants.items():
            sample=examples[key];plain=sample['plain'];mapped=sample['map'];strong=sample['strong_map'];profile=sample['recharge_profile'];count+=1
            assert plain['template_id']==row['template_id'] and plain['wave']==row['wave'] and plain['rarity']=='rare' and plain['reward_eligible'] and plain['mechanism_ids']==ids
            near(plain['health'],hp);near(plain['max_health'],hp);near(plain['max_shield'],shield);near(plain['shield'],shield)
            near(profile['base_rate'],base_rate);near(profile['rate'],rate);near(profile['delay'],4)
            near(plain['shield_regen'],base_rate);near(plain.get('shield_recharge_rate',base_rate),rate)
            near(sample['map_base_shield'],.2*hp);near(sample['map_shield_bonus'],.2*hp*(1+increase))
            near(mapped['max_shield'],shield+.2*hp*(1+increase));near(mapped['shield'],mapped['max_shield'])
            near(mapped['max_health'],hp);near(strong['max_health'],hp*1.2);near(strong['max_shield'],mapped['max_shield'])
            near(mapped['shield_regen'],base_rate);near(mapped.get('shield_recharge_rate',base_rate),rate)
            assert mapped['encounter_source']['profile']==rule['shield_map_profile'] and strong['encounter_source']['profile']==rule['strong_shield_map_profile']
            near(sample['missing_shield_preserved'],min(1,shield));near(sample['damaged_plain']['max_shield']-sample['damaged_plain']['shield'],sample['missing_shield_preserved']);near(sample['damaged_map']['max_shield']-sample['damaged_map']['shield'],sample['missing_shield_preserved'])
            if key.startswith('current'):
                frozen=plain['source_shield_profile'];assert frozen['budget_policy']==rule['budget_policy']
                near(frozen['capacity_increased'],increase);near(frozen['capacity_multiplier'],1+increase)
                near(frozen['base_max_shield'],sum(rule['supplies'][i]['max_shield'] for i in ids));near(frozen['base_recharge_rate'],base_rate)
                assert frozen['legacy_base_shield']==frozen['legacy_base_recharge_rate']==0
                assert frozen['supplies']==[dict(id=i,**rule['supplies'][i]) for i in ids]
                assert mapped['source_shield_profile']==strong['source_shield_profile']==frozen
                near(plain['max_shield'],frozen['base_max_shield']*frozen['capacity_multiplier'])
            else:assert 'source_shield_profile' not in plain
            cells=[('plain-shield',shield),('base-rate',base_rate),('rate',rate),('delay',4),('map-base',sample['map_base_shield']),('map-bonus',sample['map_shield_bonus']),('map-shield',mapped['max_shield']),('strong-life',strong['max_health']),('strong-shield',strong['max_shield']),('missing',sample['missing_shield_preserved'])]
            for name,amount in cells:rendered[prefix+'-'+key+'-'+name]=(amount,False)
    for path,expected in baseline['preserved_files'].items():assert sha((ROOT/path).read_bytes())==expected,path
    old_pngs={p for p in baseline['preserved_files'] if p.endswith('.png')};actual_pngs={str(p.relative_to(ROOT)) for folder in [ROOT/'assets',ROOT/'data',REF] for p in folder.rglob('*.png')};assert old_pngs==actual_pngs
    html=(REF/'index.html').read_text();page=Page();page.feed(html);assert len(page.ids)==len(set(page.ids))
    assert set(baseline['old_html_anchors'])<=set(page.ids)
    added=set(page.ids)-set(baseline['old_html_anchors']);assert added=={'mechanisms-source_aegis_capacity','mechanisms-source_aegis_recovery','rules-source_monster_shield_recharge'}
    assert page.values.keys()==rendered.keys(),(page.values.keys()-rendered.keys(),rendered.keys()-page.values.keys())
    for key,(amount,is_percent) in rendered.items():
        near(page.values[key],amount);assert page.labels[key].strip()==format(amount*(100 if is_percent else 1),'.12g')+('%' if is_percent else ''),key
    for link in page.links:
        if link.startswith('#'):assert link[1:] in page.ids,link
        elif link and not link.startswith(('http:','https:','mailto:')):assert (REF/link.split('#')[0]).is_file(),link
    for asset in page.assets:assert not asset.startswith(('http:','https:')) and (REF/asset).is_file(),asset
    for card in ['mechanisms-source_aegis_recovery','rules-source_monster_shield_recharge']:
        text=page.cards[card]
        for phrase in ['4% increased maximum Energy Shield','10% increased Energy Shield Recharge Rate','首条仅为摘要','完整来源包含']:assert phrase in text,(card,phrase)
    for text in ['23条历史定义','五条当前源绑定','当前共28条定义','不表示所有源基石均已共享','monster-shield-supply-v1','source_stride_v1','source_damage_life_v2','source_shield_v3','更快开始回复','玩家不会得到','独立怪物供给','缺失护盾量','有意','Canonical.Rules.VERSION']:assert text in html,text
    report={'passed':True,'baseline_commit':'76c9cab','historical_catalog_sections_preserved':preserved,'legacy_definitions_preserved':23,'old_source_definitions_preserved':3,'old_movement_and_damage_life_budgets_preserved':True,'new_source_bindings':2,'current_source_bindings':5,'total_definitions':28,'source_entries_checked':3,'dual_recovery_provenance_and_presentation':True,'monster_supply_separate_from_player_grants':True,'real_catalog_plain_and_map_cases':count,'strong_map_order_cases':count,'missing_shield_cases':count,'authoritative_html_values_and_labels_checked':len(rendered),'preserved_files':len(baseline['preserved_files']),'old_pngs_preserved':len(old_pngs),'new_art_files':0,'old_html_anchors_preserved':len(baseline['old_html_anchors']),'new_html_anchors':sorted(added),'source_coverage_byte_identical':True,'encounter_catalog_byte_identical':True,'all_anchor_and_local_file_links_valid':True,'save_version':47,'equipment_vocabulary':46,'source_policy':45,'catalog_sha256':sha((REF/'catalog.json').read_bytes()),'html_sha256':sha((REF/'index.html').read_bytes()),'scope':'Narrow runtime fragment; preserved old JSON tokens; deterministic HTML and focused values/provenance/links/preservation. No full export, import, historical combat suites, browser/UI, native launch, artwork or packaging.'}
    with (QA/'v075-preservation.json').open('x') as f:json.dump(report,f,ensure_ascii=False,indent=2);f.write('\n')
    print(json.dumps(report,ensure_ascii=False,indent=2))
if __name__=='__main__':main()

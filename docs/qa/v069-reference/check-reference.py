#!/usr/bin/env python3
"""v69 focused compiled evidence, exact permitted catalog changes and asset preservation."""
from copy import deepcopy
import hashlib,json,math,subprocess
from html.parser import HTMLParser
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3];QA=Path(__file__).resolve().parent;REF=ROOT/'docs/reference'
BASE='094c1d758f2b92ca27d42bb5207f1496b0c89768'
ENTRY='40% of Physical Damage Converted to Fire Damage'
GRANTS=[{'mode':'flat','stat':'physical_to_fire_conversion','value':0.4}]
ENTRANCES={'11505','19749','34927','37911','38320','40271','48267','63268'}
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
        if 'data-physical-fire-value' in a:
            key=a['data-physical-fire-value'];assert key not in self.values,key
            self.values[key]=float(a['data-value']);self.labels[key]='';self.active=key
    def handle_data(self,data):
        if self.active:self.labels[self.active]+=data
    def handle_endtag(self,tag):
        if tag=='strong':self.active=None

def setpath(obj,path,value):
    for key in path[:-1]:obj=obj[key]
    obj[path[-1]]=value

def main():
    old=json.loads(oldbytes('docs/reference/catalog.json'));data=json.loads((REF/'catalog.json').read_text());rule=data['physical_fire_conversion']
    assert data['game_version']=='0.69.0' and data['save_version']==rule['minimum_save_version']==rule['source_policy']==44
    assert rule['equipment_vocabulary']==39 and rule['effect_id']==65020 and rule['source_line']==ENTRY
    assert rule['fraction']==.4 and set(rule['entrances'])==ENTRANCES and rule['new_images']==[]
    assert rule['reachable_gateways']=={'11505':'29049','63268':'24324','48267':'2550','34927':'11924'}
    assert sum(row['reachable_group'] for row in rule['entrances'].values())==4
    assert len({row['group_id'] for row in rule['entrances'].values()})==8
    assert rule['class_id']==1 and rule['level']==5 and rule['point_budget']==9
    assert rule['route']==['47175','31628','9511','23881','26523','6446','10221','54396','2550']
    modes={'basic_blade':('basic','forgeblade',[]),'cleave_physical_focus':('cleave','forgeblade',['physical_focus']),'tornado_physical_focus_ignite':('tornado','ashwood_bow',['physical_focus','ignite']),'tornado_fire_focus_ember':('tornado','ashwood_bow',['fire_focus','ember_proliferation']),'tornado_added':('tornado','runewood_focus',[])}
    assert rule['examples'].keys()==modes.keys()
    rendered={'effect-id':65020,'save-version':44,'source-policy':44,'vocabulary':39,'fraction':.4,'point-budget':9}
    hit_pairs=parts_checked=focus_clauses=burn_inputs=0
    for key,pair in rule['examples'].items():
        skill,base,supports=modes[key];before,after=pair['states']['before'],pair['states']['after']
        assert (pair['skill_id'],pair['base_id'],pair['supports'])==(skill,base,supports)
        assert before['instance']==after['instance'] and len(after['instance']['affixes'])==4
        assert before['mana']==after['mana'] and before['cooldown']==after['cooldown']
        assert before['points_remaining']==1 and after['points_remaining']==0
        assert before['allocated']==rule['route'] and after['allocated']==rule['route']+['48267']
        assert before['stats']|{'physical_to_fire_conversion':.4}==after['stats']
        assert 'conversion_profile' not in before and after['conversion_profile']=={'enabled':True,'source_type':'physical','target_type':'fire','fraction':.4}
        assert before['snapshot']['modifiers']==after['snapshot']['modifiers']
        for row in [before,after]:
            assert row['whole_build_valid'] and row['save_attempts']==0
            assert sorted(row['support_ids'])==sorted(supports)
        for field in ['mana','cooldown']:rendered[key+'-'+field]=after[field]
        for state,row in pair['states'].items():rendered[key+'-points-'+state]=row['points_remaining']
        for role,prior in before['hits'].items():
            hit_pairs+=1;hit=after['hits'][role];packet=hit['packet'];prefix=key+'-'+role
            assert packet['base']==prior['packet']['base'] and packet['assembly']==prior['packet']['assembly']
            for field in ['physical','fire']:
                for state,row in pair['states'].items():rendered[prefix+'-'+field+'-'+state]=row['hits'][role]['resolved']['components'].get(field,0)
            for target in ['armour','fire_resistance']:
                for state,row in pair['states'].items():rendered[prefix+'-'+target+'-'+state]=row['hits'][role]['defended'][target]['settlement']['damage_total']
            if role=='secondary':
                assert hit==prior and not packet.get('conversion') and hit['resolved']['components']['fire']>0
                continue
            split=packet['conversion'];assembly=packet['assembly'];physical=packet['base']['physical']
            assert split=={'source_type':'physical','target_type':'fire','fraction':.4,'source_base':physical,'remaining_base':physical*(1-.4),'converted_base':physical*.4}
            near(physical,assembly['intrinsic'].get('physical',0)+assembly['added'].get('physical',0)+assembly.get('weapon',{}).get('contribution',{}).get('physical',0))
            for field,amount in [('source',physical),('intrinsic',assembly['intrinsic'].get('physical',0)),('added',assembly['added'].get('physical',0)),('weapon',assembly.get('weapon',{}).get('contribution',{}).get('physical',0)),('remaining',split['remaining_base']),('converted',split['converted_base'])]:rendered[prefix+'-'+field]=amount
            assert {d['type'] for d in hit['resolved']['details']}==set(hit['resolved']['components'])=={'physical','fire'}
            assert len(hit['resolved']['details'])==2
            for detail in hit['resolved']['details']:
                near(detail['before_defense'],sum(p['before_defense'] for p in detail['parts']))
                for index,part in enumerate(detail['parts']):
                    parts_checked+=1;pkey=prefix+'-'+detail['type']+'-part'+str(index)
                    assert set(part)=={'lineage','base','increased','more','before_defense','modifiers','modifier_indices'}
                    assert len(part['modifier_indices'])==len(set(part['modifier_indices']))==len(part['modifiers'])
                    near(part['before_defense'],part['base']*(1+part['increased'])*part['more'])
                    for field in ['base','increased','more','before_defense']:rendered[pkey+'-'+field]=part[field]
                    if part['lineage']==['physical','fire']:
                        near(part['base'],physical*.4)
                        focus=[(i,mid) for i,mid in zip(part['modifier_indices'],part['modifiers']) if mid in ['support:physical_focus','support:fire_focus']]
                        if any('focus' in sid for sid in supports):
                            assert len(focus)==2 and focus[0][0]!=focus[1][0] and focus[0][1]==focus[1][1]
                            amounts=[after['snapshot']['modifiers'][i]['value'] for i,_ in focus]
                            assert sorted(amounts)==[-.2,.2];near(math.prod(1+x for x in amounts),.96);focus_clauses+=2
                    elif part['lineage']==['physical']:near(part['base'],physical*.6)
                    else:assert part['lineage']==['fire'];near(part['base'],packet['base']['fire'])
            for target,defended in hit['defended'].items():
                assert defended['settlement']['ok'] and len(defended['resolved']['details'])==2
                near(defended['settlement']['damage_total'],sum(defended['resolved']['components'].values()))
            if key=='tornado_added':assert assembly['added']['physical']>0 and assembly['added']['fire']>0
            else:assert assembly['weapon']['contribution']['physical']>0
        if 'burn_profile' in after:
            for state,row in pair['states'].items():
                profile=row['burn_profile'];assert set(profile['roles'])=={'parent','child'}
                for role,burn in profile['roles'].items():
                    burn_inputs+=1;near(burn['fire_before_defense'],row['hits'][role]['resolved']['components']['fire'])
                    near(burn['dps'],burn['fire_before_defense']*profile['rate_fraction']*(1+profile.get('fire_dot_multiplier',0))*(1+profile.get('burn_faster',0)))
                    near(burn['total'],burn['dps']*profile['duration'])
                    for field in ['fire_before_defense','dps','total']:rendered[key+'-burn-'+role+'-'+field+'-'+state]=burn[field]
            assert before['burn_profile']['duration']==after['burn_profile']['duration']==3
            rendered[key+'-burn-duration']=after['burn_profile']['duration']
        else:assert 'burn_profile' not in before
    page=Page();html=(REF/'index.html').read_text();page.feed(html)
    assert page.values.keys()==rendered.keys(),(page.values.keys()-rendered.keys(),rendered.keys()-page.values.keys())
    for key,value in rendered.items():near(page.values[key],value);assert page.labels[key].strip()==format(value,'.10g'),(key,page.labels[key],value)
    assert len(page.ids)==len(set(page.ids)) and 'rules-physical_fire_conversion' in page.ids
    oldpage=Page();oldpage.feed(oldbytes('docs/reference/index.html').decode());assert set(oldpage.ids)<=set(page.ids)
    for link in page.links:
        if link.startswith('#'):assert link[1:] in page.ids,link
        elif link and not link.startswith(('http:','https:','mailto:')):assert (REF/link.split('#')[0]).is_file(),link
    for asset in page.assets:assert not asset.startswith(('http:','https:')) and (REF/asset).is_file(),asset
    for wording in ['×1.20再×0.80＝×0.96','modifier_indices','原生火焰','残余物理','8个入口共享唯一效果','schema43→44','物理攻击偷取','已在途母箭']:
        assert wording in html,wording
    # The exact old catalog is reconstructed with the only authorized changes.
    expected=deepcopy(old);expected['physical_fire_conversion']=rule;expected['game_version']='0.69.0'
    paths=[('save_version',),('canonical','default_build','version'),('canonical','save_version'),('crafting','calibration_shard','save_version'),('currencies','calibration_shard','save_version'),('melee_basic','save_version'),('normal_gem_trading','schema'),('sunwell_terrace','save_version'),('town_maps','save_version')]
    for op in ['augment','elevate','enchant','recalibrate','reforge','salvage','targeted_reforge_critical','targeted_reforge_damage','targeted_reforge_life_leech','targeted_reforge_mana_leech']:paths.append(('crafting',op,'example','save_version'))
    for path in paths:
        value=old
        for key in path:value=value[key]
        assert value==43;setpath(expected,path,44)
    for chapter in ['defense_rating_affixes','resolute_technique','elemental_defense_affixes','elemental_resistance_caps','iron_reflexes','zealots_oath','inward_pull','ambush']:
        assert old[chapter]['source_policy']==41;expected[chapter]['source_policy']=44
    for node_id in ENTRANCES:
        choices=expected['source_tree']['nodes'][node_id]['mastery_choices'];choice=next(row for row in choices if row['effect']==65020)
        assert choice['stats']==[ENTRY] and choice['execution']=={'status':'unsupported','grants':[],'supported':[],'unsupported':[ENTRY]}
        choice['execution']={'status':'full','grants':GRANTS,'supported':[ENTRY],'unsupported':[]}
        localized=expected['source_tree_localization']['nodes'][node_id]['mastery_choices'];assert localized['65020'].endswith('（暂未实装）');localized['65020']=localized['65020'].removesuffix('（暂未实装）')
    line=expected['source_tree_localization']['lines'][ENTRY];line['text']=line['text'].removesuffix('（暂未实装）');line['status'].update(implemented=True,parser_supported=True,grants=GRANTS)
    assert expected==data,list(differences(expected,data))[:8]
    oldcoverage=json.loads(oldbytes('docs/reference/source-tree-coverage.json'));coverage=json.loads((REF/'source-tree-coverage.json').read_text());projected=deepcopy(oldcoverage)
    for node in projected['nodes']:
        if node['id'] in ENTRANCES:
            option=next(x for x in node['mastery_options'] if x['effect_id']==65020)
            option['execution'].update(api_status='full',coverage_status='full',grants=GRANTS,supported=[ENTRY],unsupported=[])
    for partition in ['all_source','standard_allocation_graph']:
        for field in ['mastery_option_status_counts','node_direct_effect_status_counts','direct_effect_entries']:
            projected['effect_coverage'][partition][field]['full']+=8
            projected['effect_coverage'][partition][field]['unsupported']-=8
    assert projected==coverage,list(differences(projected,coverage))[:8]
    paths=subprocess.check_output(['git','ls-tree','-r','--name-only',BASE,'assets','data','docs/reference'],cwd=ROOT,text=True).splitlines()
    preserved=[p for p in paths if p.endswith('.png') or p.startswith('data/')]
    preserved+=['docs/reference/reference.css','docs/reference/reference.js','docs/reference/art/manifest.json']
    hashes={p:sha((ROOT/p).read_bytes()) for p in preserved}
    for path,current in hashes.items():assert current==sha(oldbytes(path)),path
    old_pngs=[p for p in paths if p.endswith('.png')]
    assert sorted(old_pngs)==sorted(p.relative_to(ROOT).as_posix() for folder in [ROOT/'assets',REF] for p in folder.rglob('*.png'))
    changes=list(differences(old,data));coverage_changes=list(differences(oldcoverage,coverage))
    report={'passed':True,'baseline_commit':BASE,'production_compiler_representative_pairs':len(modes),'individual_hit_pairs':hit_pairs,'lineage_parts_checked':parts_checked,'focus_independent_clauses_checked':focus_clauses,'burn_final_fire_inputs_checked':burn_inputs,'authoritative_html_values_and_visible_labels_checked':len(rendered),'html_unique_ids':len(page.ids),'old_html_anchors_preserved':len(oldpage.ids),'all_anchor_and_local_file_links_valid':True,'old_default_build_and_skill_examples_preserved':True,'exact_catalog_approved_changed_paths':len(changes),'source_coverage_approved_changed_paths':len(coverage_changes),'full_mastery_entries_before_after':[37,45],'ordinary_node_reachability_unchanged':True,'raw_source_and_chinese_mapping_files_byte_identical':True,'old_asset_pngs_preserved':len([p for p in old_pngs if p.startswith('assets/')]),'old_reference_pngs_preserved':len([p for p in old_pngs if p.startswith('docs/reference/')]),'catalog_bytes':(REF/'catalog.json').stat().st_size,'catalog_sha256':sha((REF/'catalog.json').read_bytes()),'html_sha256':sha((REF/'index.html').read_bytes()),'coverage_sha256':sha((REF/'source-tree-coverage.json').read_bytes()),'unchanged_files':hashes,'changes':[{'kind':kind,'path':list(path),'before_sha256':digest(left),'after_sha256':digest(right)} for kind,path,left,right in changes]}
    receipt=QA/'v068-preservation.json'
    if receipt.exists():assert json.loads(receipt.read_text())==report,'Existing preservation receipt differs'
    else:
        with receipt.open('x') as f:json.dump(report,f,ensure_ascii=False,indent=2);f.write('\n')
    print(json.dumps({key:value for key,value in report.items() if key not in ['changes','unchanged_files']},ensure_ascii=False,indent=2))
if __name__=='__main__':main()

#!/usr/bin/env python3
"""v61 authoritative examples, rendered values, complete bounded v60 projection."""
from copy import deepcopy
import hashlib
from html.parser import HTMLParser
import json
import math
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[3]
QA=ROOT/'docs/qa/v061-reference'
REF=ROOT/'docs/reference'
BASE='b389993ed7f7a90f4043c668704583d44b22f343'
ENTRY="Your hits can't be Evaded\nNever deal Critical Strikes"
GRANTS=[{'stat':'resolute_technique','value':1.0,'mode':'flat'}]
POLICY={'id':'resolute_technique','hits_cannot_be_evaded':True,'cannot_deal_critical_strikes':True}
def decode(raw):return json.loads(raw,parse_int=float,parse_float=float)
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def digest(value):return hashlib.sha256(json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def near(a,b):assert math.isfinite(a) and abs(a-b)<max(1e-9,abs(b)*1e-12),(a,b)
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
        if 'data-resolute-value' in attrs:
            assert self.article=='rules-resolute_technique'
            key=attrs['data-resolute-value'];assert key not in self.values
            self.values[key]=float(attrs['data-value'])
    def handle_endtag(self,tag):
        if tag=='article':self.article=None
    def handle_data(self,data):self.text.append(data)
def coverage_expected(old,data):
    expected=deepcopy(old)
    node=next(n for n in expected['nodes'] if n['id']=='31961')
    assert node['execution']=={'api_status':'unsupported','coverage_status':'unsupported','grants':[],'has_direct_stats':True,'supported':[],'unsupported':[ENTRY]}
    node['execution']={'api_status':'full','coverage_status':'full','grants':GRANTS,'has_direct_stats':True,'supported':[ENTRY],'unsupported':[]}
    for area in ['all_source','standard_allocation_graph']:
        for group in ['direct_effect_entries','node_api_status_counts','node_direct_effect_status_counts']:
            expected['effect_coverage'][area][group]['full']+=1
            expected['effect_coverage'][area][group]['unsupported']-=1
    for row in expected['class_reachability']:
        frontier=[n for n in row['blocked_frontier'] if n['node_id']=='31961'];assert len(frontier)==1 and frontier[0]['status']=='unsupported'
        row['blocked_frontier'].remove(frontier[0]);row['blocked_frontier_count']-=1;row['blocked_frontier_status_counts']['unsupported']-=1
        for key in ['reachable_count_excluding_start','reachable_count_including_start','reachable_full_direct_effect_nodes']:row[key]+=1
        row['reachable_node_ids_including_start'].append('31961');row['reachable_node_ids_including_start'].sort()
    assert data==expected, list(differences(expected,data))[:5]
    return expected

def main():
    old=decode(subprocess.check_output(['git','show',BASE+':docs/reference/catalog.json'],cwd=ROOT))
    data=decode((REF/'catalog.json').read_bytes());r=data['resolute_technique'];page=Page();page.feed((REF/'index.html').read_text())
    assert data['game_version']=='0.61.0' and data['save_version']==r['minimum_save_version']==r['source_policy']==38 and r['equipment_vocabulary']==37
    assert r['node']['id']=='31961' and r['node']['name']=='Resolute Technique' and r['node']['source_lines']==[ENTRY]
    assert r['node']['execution']=={'status':'full','supported':[ENTRY],'unsupported':[],'grants':GRANTS}
    assert data['source_tree']['nodes']['31961']['execution']==r['node']['execution']
    assert r['node']['legacy_execution']==old['source_tree']['nodes']['31961']['execution']
    assert data['source_tree_localization']['nodes']['31961']['stats']=='你的击中无法被闪避\n不会造成暴击'
    expected_line=deepcopy(old['source_tree_localization']['lines'][ENTRY])
    expected_line['text']='你的击中无法被闪避\n不会造成暴击'
    expected_line['status'].update({'implemented':True,'parser_supported':True,'grants':GRANTS})
    assert data['source_tree_localization']['lines'][ENTRY]==expected_line
    assert r['new_complete_ordinary_nodes']==['31961'] and r['new_mastery_effect_ids']==r['new_images']==[] and r['policy']==POLICY
    assert r['required_level']==7 and r['points_spent']==11 and len(r['route'])==12
    before,after=r['examples']['before'],r['examples']['after']
    assert before['whole_build_valid'] and after['whole_build_valid'] and before['save_attempts']==after['save_attempts']==0
    assert before['equipment']==after['equipment']=={'weapon':'prism_bow','amulet':'detonation_charm'}
    assert before['talents']['allocated']==r['route'][:-1] and after['talents']['allocated']==r['route']
    assert before['talents']['normal_points']==1 and after['talents']['normal_points']==0
    for left,right in zip(r['route'],r['route'][1:]):assert right in data['source_tree']['nodes'][left]['neighbors']
    assert before['stats']['resolute_technique']==0 and after['stats']['resolute_technique']==1
    projected=deepcopy(after['stats']);projected['resolute_technique']=0;assert projected==before['stats']
    assert 'resolute_technique' not in before['snapshot'] and after['snapshot']['resolute_technique']==1
    assert all(node['execution']['status']!='full' for node in r['blocked_matching_nodes'].values())
    rendered={'required-level':7,'points-spent':11,'save-version':38,'source-policy':38,'equipment-vocabulary':37}
    compared_hits=0
    for skill,cast in after['casts'].items():
        prior=before['casts'][skill]
        assert cast['hit_policy']==POLICY and prior['hit_policy']=={}
        assert cast['recipe']==prior['recipe'] and cast['mana']==prior['mana'] and cast['cooldown']==prior['cooldown']
        assert '不能造成暴击' in cast['details'] and '暴击伤害' not in cast['details']
        for role,hit in cast['hits'].items():
            original=prior['hits'][role];assert hit['packet']==original['packet']
            assert hit['critical']['chance']==0 and hit['critical']['multiplier']==original['critical']['multiplier']
            assert original['critical']['chance']>0
            for target_id,case in hit['targets'].items():
                old_case=original['targets'][target_id]
                assert case['admission']['chance']==1 and case['admission']['entropy']==50 and case['admission']['hit']
                assert case['successful_noncritical_hit']==old_case['successful_noncritical_hit']
                near(case['expected_per_attempt'],case['successful_noncritical_hit']['total'])
                old_mean=old_case['successful_noncritical_hit']['total']*(1-original['critical']['chance'])+old_case['potential_critical_hit']['total']*original['critical']['chance']
                near(old_case['expected_per_successful_hit'],old_mean);near(old_case['expected_per_attempt'],old_mean*old_case['admission']['chance'])
                if 'attack' not in hit['packet']['tags']:assert old_case['admission']['chance']==1
            stem=skill+'-'+role
            rendered.update({stem+'-before-crit':original['critical']['chance'],stem+'-after-crit':0,stem+'-before-expected':original['targets']['no_evasion']['expected_per_attempt'],stem+'-after-expected':hit['targets']['no_evasion']['expected_per_attempt']})
            assert hit['targets']['no_evasion']['expected_per_attempt']<original['targets']['no_evasion']['expected_per_attempt']
            compared_hits+=1
    assert before['casts']['basic']['hits']['projectile']['targets']['evasive']['admission']['chance']<1
    assert before['casts']['basic']['hits']['projectile']['targets']['no_evasion']['admission']['chance']==1
    for target in ['evasive','no_evasion']:
        rendered[target+'-evasion']=r['targets'][target]['evasion']
        for mode,state in [('before',before),('after',after)]:
            case=state['casts']['basic']['hits']['projectile']['targets'][target];stem=target+'-'+mode
            rendered.update({stem+'-chance':case['admission']['chance'],stem+'-successful':case['successful_noncritical_hit']['total'],stem+'-expected':case['expected_per_attempt']})
    rendered['target-armour']=r['defense_profile']['armour'];assert rendered['target-armour']==500
    for element in ['fire','cold','lightning']:
        rendered['target-'+element+'-resistance']=r['defense_profile']['effective_resistances'][element];near(rendered['target-'+element+'-resistance'],.75)
    for skill,role in [('basic','projectile'),('cleave','direct'),('nova','direct'),('tornado','secondary')]:
        hit=after['casts'][skill]['hits'][role];stem='defense-'+skill+'-'+role
        raw=hit['targets']['no_evasion']['successful_noncritical_hit']['total'];reduced=hit['targets']['armour_and_capped_resistance']['successful_noncritical_hit']['total']
        assert reduced<raw;rendered.update({stem+'-before':raw,stem+'-after':reduced})
    assert page.values.keys()==rendered.keys(),(page.values.keys()-rendered.keys(),rendered.keys()-page.values.keys())
    for key,value in rendered.items():near(page.values[key],value)
    assert len(page.ids)==len(set(page.ids)) and 'rules-resolute_technique' in page.ids
    for target in page.links:
        if target.startswith('#'):assert target[1:] in page.ids,target
        elif target and not target.startswith(('https://','http://','mailto:')):assert (REF/target.split('#')[0]).exists(),target
    for asset in page.assets:assert not asset.startswith(('http:','https:')) and (REF/asset).exists(),asset
    # Reconcile only exact versions, zero-valued aggregate fields, and31961's
    # current execution/display projection. No legacy category is discarded.
    zero_paths={('canonical','default_stats'),('configurations','fresh','stats'),('elemental_resistance_caps','reachable_build','stats')}
    zero_paths.update(('elemental_defense_affixes','examples',key,'stats') for key in ['mana_recovery','six_max','white_base'])
    zero_paths.update(('mana_guard','class_paths',index,'stats') for index in range(7))
    zero_paths.update(('melee_basic','equipped_examples',key,'stats') for key in ['normal','six_t3_max'])
    zero_paths.update(('monster_attacks',attack,'example','cases',case,'defense_stats') for attack in ['locked_circle_cold','locked_circle_lightning'] for case in ['armored','moving','standing'])
    zero_paths.update(('source_fire_dot','legal_build_examples',index,'stats') for index in range(3))
    zero_paths.add(('source_faster_burn','legal_build_examples',0,'stats'))
    approved=[];projection=deepcopy(data)
    for kind,path,left,right in differences(old,data):
        category=None
        if kind=='added' and path==('resolute_technique',):category='single_new_rule_section'
        elif path==('game_version',) and left=='0.60.0' and right=='0.61.0':category='game_version'
        elif path[-1] in ['version','save_version','schema'] and left==37 and right==38:category='current_save_version'
        elif path in [('elemental_resistance_caps','source_policy'),('elemental_defense_affixes','source_policy')] and left==36 and right==38:category='current_source_policy'
        elif kind=='added' and path[-1]=='resolute_technique' and right==0 and path[:-1] in zero_paths:category='zero_derived_stat'
        elif path[:4]==('source_tree','nodes','31961','execution'):category='exact_node_execution'
        elif path==('source_tree_localization','nodes','31961','stats'):category='exact_node_localized_status'
        elif path[:3]==('source_tree_localization','lines',ENTRY):category='exact_whole_entry_localized_status'
        assert category is not None,(kind,path,left,right)
        at=projection
        for part in path[:-1]:at=at[part]
        if kind=='added':del at[path[-1]]
        else:at[path[-1]]=left
        approved.append({'kind':kind,'path':list(path),'category':category,'before':left,'after_sha256':digest(right)})
    assert projection==old and digest(projection)==digest(old)
    for key in ['equipment','affixes','fixed_items','equipment_pools','loot_profiles','current_loot_profile','current_loot_profile_id']:
        assert data[key]==old[key],key
    old_coverage=decode(subprocess.check_output(['git','show',BASE+':docs/reference/source-tree-coverage.json'],cwd=ROOT))
    coverage=decode((REF/'source-tree-coverage.json').read_bytes());coverage_expected(old_coverage,coverage)
    baseline=json.loads((QA/'v060-baseline.json').read_text())
    for group,count in [('asset_pngs',61),('reference_pngs',68)]:
        assert len(baseline[group])==count and {p:sha(ROOT/p) for p in baseline[group]}==baseline[group]
    report={'passed':True,'baseline_commit':BASE,'old_catalog_semantic_sha256':digest(old),'current_catalog_semantic_sha256':digest(data),'projected_catalog_semantic_sha256':digest(projection),
        'approved_changed_leaves':len(approved),'rendered_authoritative_values_checked':len(rendered),'before_after_hit_roles_checked':compared_hits,'html_ids':len(page.ids),'all_html_anchor_and_local_asset_links_valid':True,
        'equipment_and_loot_data_unchanged':True,'old_asset_pngs_unchanged':61,'old_reference_pngs_unchanged':68,'font_verification':'Separate affected-only font-addition-preservation.json; initial full runtime scan retained',
        'source_coverage_exact_one_node_opened':True,'source_coverage_other_nodes_masteries_geometry_preserved':True,'source_coverage_current_sha256':digest(coverage),'approved_changes':approved}
    save('v060-projection-preservation.json',report)
    print(json.dumps({k:v for k,v in report.items() if k!='approved_changes'},ensure_ascii=False,indent=2))
if __name__=='__main__':main()

#!/usr/bin/env python3
"""Focused v66 display, production export and bounded v65 catalog preservation."""
from copy import deepcopy
import hashlib,json,math,subprocess
from html.parser import HTMLParser
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3];QA=Path(__file__).resolve().parent;REF=ROOT/'docs/reference';BASE='b2bd4a1'
def sha(raw):return hashlib.sha256(raw).hexdigest()
def digest(value):return sha(json.dumps(value,sort_keys=True,ensure_ascii=False,separators=(',',':')).encode())
def oldbytes(path):return subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT)
def near(left,right):assert math.isfinite(left) and abs(left-right)<=max(1e-8,abs(right)*1e-10),(left,right)
def differences(left,right,path=()):
    if isinstance(left,dict) and isinstance(right,dict):
        for key in sorted(left.keys()|right.keys()):
            if key not in left:yield 'added',path+(key,),None,right[key]
            elif key not in right:yield 'removed',path+(key,),left[key],None
            else:yield from differences(left[key],right[key],path+(key,))
    elif isinstance(left,list) and isinstance(right,list) and len(left)==len(right):
        for i,(a,b) in enumerate(zip(left,right)):yield from differences(a,b,path+(i,))
    elif left!=right:yield 'changed',path,left,right
class Page(HTMLParser):
    def __init__(self):super().__init__();self.ids=[];self.links=[];self.assets=[];self.values={};self.labels={};self.active=None
    def handle_starttag(self,tag,attrs):
        attrs=dict(attrs)
        if 'id' in attrs:self.ids.append(attrs['id'])
        if 'href' in attrs:self.links.append(attrs['href'])
        if 'src' in attrs:self.assets.append(attrs['src'])
        if 'data-ambush-value' in attrs:
            key=attrs['data-ambush-value'];assert key not in self.values
            self.values[key]=float(attrs['data-value']);self.labels[key]='';self.active=key
    def handle_data(self,data):
        if self.active:self.labels[self.active]+=data
    def handle_endtag(self,tag):
        if tag=='strong':self.active=None
def setpath(value,path,replacement):
    for key in path[:-1]:value=value[key]
    value[path[-1]]=replacement
def main():
    old=json.loads(oldbytes('docs/reference/catalog.json'));data=json.loads((REF/'catalog.json').read_text());rule=data['ambush']
    page=Page();html=(REF/'index.html').read_text();page.feed(html)
    policy={'enabled':True,'arming_seconds':.35,'trigger_radius':70.0,'lifetime_seconds':12.0,'maximum_traps':3,'hit_multiplier':.85,'mana_multiplier':1.25}
    assert rule['policy']==policy and rule['skills']==['nova','meteor']
    assert data['game_version']=='0.66.0' and data['save_version']==rule['minimum_save_version']==42
    assert rule['source_policy']==41 and rule['equipment_vocabulary']==39
    assert rule['example_stats']==data['configurations']['fresh']['stats']
    assert rule['merchant_quote']['cost']=={'calibration_shard':4}
    assert rule['merchant_quote']['ok'] and rule['test_offer']['available'] and rule['test_offer']['price_label']=='测试免费'
    assert not rule['normal_reward_pool_includes_support'] and rule['normal_reward_definition_count']==26
    assert data['canonical']['gem_reward']['definition_count']==30
    modes={'nova':{'base':[],'shock':['shock'],'wide':['breadth'],'concentrated':['concentrate'],'combined_area':['breadth','concentrate']},'meteor':{'base':[],'ignite':['ignite'],'ember':['ember_proliferation'],'combined_area':['breadth','concentrate']}}
    rendered={'save-version':42,'source-policy':41,'vocabulary':39,'arming':.35,'trigger-radius':70,'lifetime':12,'maximum-traps':3,'hit-multiplier':.85,'mana-multiplier':1.25,'merchant-cost':4,'reward-count':26}
    checked=0
    for skill,examples in rule['examples'].items():
        assert examples.keys()==modes[skill].keys()
        for mode,pair in examples.items():
            checked+=1;before,after=pair['before'],pair['after'];prefix=skill+'-'+mode
            assert sorted(before['support_ids'])==sorted(modes[skill][mode])
            assert sorted(after['support_ids'])==sorted(modes[skill][mode]+['ambush'])
            assert after['trap_profile']==policy and 'trap_profile' not in before
            assert after['recipe']==before['recipe'] and after['cooldown']==before['cooldown']
            assert after['packet']==before['packet'] and set(after['packet']['tags'])=={'hit','spell','area'}
            assert after['critical']==before['critical']
            near(after['mana'],before['mana']*policy['mana_multiplier'])
            near(after['resolved']['total'],before['resolved']['total']*policy['hit_multiplier'])
            for kind,value in before['resolved']['components'].items():near(after['resolved']['components'][kind],value*policy['hit_multiplier'])
            for state,row in pair.items():
                for field,value in [('hit',row['resolved']['total']),('mana',row['mana']),('cooldown',row['cooldown']),('radius',row['recipe']['radius'])]:rendered[prefix+'-'+field+'-'+state]=value
            rendered[prefix+'-trigger-radius']=policy['trigger_radius']
            if 'shock_profile' in after:
                status=after['shock_profile'];assert skill=='nova' and mode=='shock' and status==before['shock_profile']
                assert status['applies_after_current_hit'] and status['affects_hits_only'] and not status['affects_dot'] and status['roles']==['direct']
                rendered[prefix+'-shock-duration']=status['duration'];rendered[prefix+'-shock-increased']=status['hit_damage_taken_increased']
            if 'burn_profile' in after:
                status=after['burn_profile'];direct=status['roles']['direct'];prior=before['burn_profile']['roles']['direct']
                assert skill=='meteor' and mode in ['ignite','ember'] and status['duration']==before['burn_profile']['duration']
                for field in ['fire_before_defense','dps','total']:near(direct[field],prior[field]*policy['hit_multiplier'])
                near(direct['total'],direct['dps']*status['duration'])
                projected=deepcopy(status);projected['roles']=before['burn_profile']['roles'];assert projected==before['burn_profile']
                rendered[prefix+'-burn-duration']=status['duration'];rendered[prefix+'-burn-dps']=direct['dps'];rendered[prefix+'-burn-total']=direct['total']
                if 'proliferation' in status:
                    assert mode=='ember'
                    rendered[prefix+'-ember-radius']=status['proliferation']['radius'];rendered[prefix+'-ember-targets']=status['proliferation']['max_targets']
    assert checked==9 and len(rendered)==102
    assert page.values.keys()==rendered.keys(),(page.values.keys()-rendered.keys(),rendered.keys()-page.values.keys())
    for key,value in rendered.items():near(page.values[key],value);near(float(page.labels[key].strip()),value)
    assert len(page.ids)==len(set(page.ids)) and all(key in page.ids for key in ['supports-ambush','rules-ambush'])
    for link in page.links:
        if link.startswith('#'):assert link[1:] in page.ids,link
        elif link and not link.startswith(('http:','https:','mailto:')):assert (REF/link.split('#')[0]).is_file(),link
    for asset in page.assets:assert not asset.startswith(('http:','https:')) and (REF/asset).is_file(),asset
    for text in ['不立即造成命中','共享','未触发过期','快照','cast_id=0','phase=trap','不开放陷阱伤害','固定模拟tick','源政策41','装备词汇39']:assert text in html,text
    # An explicit new delivery chapter and bounded metadata additions. No
    # existing cast row, equipment value, source effect or reward identity may change.
    expected=deepcopy(old);expected['ambush']=rule;expected['game_version']='0.66.0'
    paths={('save_version',),('canonical','default_build','version'),('canonical','save_version'),('crafting','calibration_shard','save_version'),('currencies','calibration_shard','save_version'),('melee_basic','save_version'),('normal_gem_trading','schema'),('sunwell_terrace','save_version'),('town_maps','save_version')}
    for operation in ['augment','elevate','enchant','recalibrate','reforge','salvage','targeted_reforge_critical','targeted_reforge_damage','targeted_reforge_life_leech','targeted_reforge_mana_leech']:paths.add(('crafting',operation,'example','save_version'))
    for path in paths:
        value=old
        for key in path:value=value[key]
        assert value==41,(path,value)
        setpath(expected,path,42)
    for field in ['supports','support_program_examples']:expected[field]['ambush']=data[field]['ambush']
    definition=data['canonical']['gem_definitions']['support:ambush']
    assert definition['name']=='符印伏击辅助' and definition['skills']==rule['skills'] and definition['icon']==rule['icon_source']
    expected['canonical']['gem_definitions']['support:ambush']=definition
    expected['canonical']['gem_reward']['definition_count']+=1
    for skill in rule['skills']:expected['skills'][skill]['compatible_supports'].append('ambush')
    for path in [('normal_gem_trading','offers'),('town_maps','stock','skill_merchant')]:
        prior=old;current=data
        for key in path:prior=prior[key];current=current[key]
        additions=[(index,row) for index,row in enumerate(current) if row['definition_id']=='support:ambush']
        assert len(additions)==1 and len(current)==len(prior)+1
        index,addition=additions[0];projected=deepcopy(prior);projected.insert(index,addition);assert projected==current
        setpath(expected,path,projected)
    assert expected==data,list(differences(expected,data))[:4]
    assert data['normal_journey']==old['normal_journey'] and data['source_tree']==old['source_tree']
    assert data['support_program_examples']['ambush']['family']=='ambush'
    for skill,pair in data['support_program_examples']['ambush']['examples'].items():
        assert skill in rule['skills'] and pair['after']['trap_profile']==policy and 'trap_profile' not in pair['before']
    old_pngs=[path for path in subprocess.check_output(['git','ls-tree','-r','--name-only',BASE,'assets','docs/reference'],cwd=ROOT,text=True).splitlines() if path.endswith('.png')]
    assert len([path for path in old_pngs if path.startswith('assets/')])==61 and len([path for path in old_pngs if path.startswith('docs/reference/')])==68
    assert len(list((ROOT/'assets').rglob('*.png')))==62 and len(list(REF.rglob('*.png')))==69
    preserved=old_pngs+['docs/reference/reference.css','docs/reference/reference.js','docs/reference/art/manifest.json','docs/reference/source-tree-coverage.json']
    hashes={path:sha((ROOT/path).read_bytes()) for path in preserved}
    for path,current in hashes.items():assert current==sha(oldbytes(path)),path
    icon=ROOT/rule['icon_source'].removeprefix('res://');copy=REF/rule['icon_file'];assert icon.read_bytes()==copy.read_bytes()
    changes=list(differences(old,data))
    report={'passed':True,'baseline_commit':subprocess.check_output(['git','rev-parse',BASE],cwd=ROOT,text=True).strip(),'production_compiler_representative_pairs':checked,'authoritative_html_values_and_visible_labels_checked':len(rendered),'html_unique_ids':len(page.ids),'all_anchor_and_local_file_links_valid':True,'approved_catalog_changed_paths':len(changes),'all_old_skill_examples_and_support_programs_unchanged':True,'source_coverage_and_frozen_26_reward_identities_unchanged':True,'old_asset_pngs_preserved':61,'old_reference_pngs_preserved':68,'new_asset_and_reference_png_counts':[62,69],'ambush_reference_copy_sha256':sha(copy.read_bytes()),'current_catalog_semantic_sha256':digest(data),'unchanged_files':hashes,'changes':[{'kind':kind,'path':list(path),'before_sha256':digest(left),'after_sha256':digest(right)} for kind,path,left,right in changes]}
    receipt=QA/'v065-preservation.json'
    if receipt.exists():assert json.loads(receipt.read_text())==report,'Existing preservation receipt differs'
    else:
        with receipt.open('x') as file:json.dump(report,file,ensure_ascii=False,indent=2);file.write('\n')
    print(json.dumps({key:value for key,value in report.items() if key not in ['changes','unchanged_files']},ensure_ascii=False,indent=2))
if __name__=='__main__':main()

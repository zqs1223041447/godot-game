#!/usr/bin/env python3
"""Current Godot projections, rendered cap values, bounded v58 preservation."""
from copy import deepcopy
import hashlib
from html.parser import HTMLParser
import json
import math
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[3]
QA=ROOT/'docs/qa/v059-reference'
REF=ROOT/'docs/reference'
BASE='71f4863fda4b02d1afd17db4cfa958c85139491f'
FIELDS={f'maximum_{e}_resistance_add' for e in ['fire','cold','lightning']}
OPEN={'15522','24133','25989','34917','42009','45341','48929','50029','5065','53118','60031','6043'}
MIXED={'11820','1581','20832','33676','40743','54798'}
OFFGRAPH={'38683','42313','44203','48803','54766'}
AFFECTED=OPEN|MIXED|OFFGRAPH


def decode(raw): return json.loads(raw,parse_int=float,parse_float=float)
def digest(value): return hashlib.sha256(json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def near(a,b): assert math.isfinite(a) and abs(a-b)<1e-9,(a,b)
def save(name,value):
    with (QA/name).open('x') as stream: json.dump(value,stream,ensure_ascii=False,indent=2);stream.write('\n')


def differences(a,b,path=()):
    if isinstance(a,dict) and isinstance(b,dict):
        for key in sorted(a.keys()|b.keys()):
            if key not in a: yield 'added',path+(key,),None,b[key]
            elif key not in b: yield 'removed',path+(key,),a[key],None
            else: yield from differences(a[key],b[key],path+(key,))
    elif isinstance(a,list) and isinstance(b,list) and len(a)==len(b):
        for i,(left,right) in enumerate(zip(a,b)): yield from differences(left,right,path+(i,))
    elif a!=b: yield 'changed',path,a,b


class Page(HTMLParser):
    def __init__(self):
        super().__init__();self.ids=[];self.links=[];self.assets=[];self.values={};self.article=None
    def handle_starttag(self,tag,attrs):
        attrs=dict(attrs)
        if 'id' in attrs:self.ids.append(attrs['id'])
        if tag=='article':self.article=attrs.get('id')
        if tag=='a':self.links.append(attrs.get('href',''))
        if tag in ['img','link','script']:
            asset=attrs.get('src',attrs.get('href',''))
            if asset:self.assets.append(asset)
        if 'data-resistance-cap-value' in attrs:
            assert self.article=='rules-elemental_resistance_caps'
            key=attrs['data-resistance-cap-value'];assert key not in self.values
            self.values[key]=float(attrs['data-value'])
    def handle_endtag(self,tag):
        if tag=='article':self.article=None


def main():
    old=decode(subprocess.check_output(['git','show',BASE+':docs/reference/catalog.json'],cwd=ROOT))
    data=decode((REF/'catalog.json').read_bytes());caps=data['elemental_resistance_caps']
    assert data['game_version']=='0.59.0' and data['save_version']==caps['minimum_save_version']==caps['source_policy']==36
    near(caps['base_cap'],.75);near(caps['safety_cap'],.83)
    assert caps['source_sha256']==data['source_tree']['source_sha256']==old['source_tree']['source_sha256']
    assert caps['source_version']==data['source_tree']['source_version']=='3.29.1'
    assert set(caps['nodes'])==set(caps['new_complete_ordinary_nodes'])==OPEN
    changed_nodes=[]
    for key,node in data['source_tree']['nodes'].items():
        prior=old['source_tree']['nodes'][key]
        fresh_core={k:v for k,v in node.items() if k!='execution'}
        old_core={k:v for k,v in prior.items() if k!='execution'}
        assert fresh_core==old_core,('source raw, graph or mastery changed',key)
        if node['execution']!=prior['execution']:
            changed_nodes.append(key);assert key in AFFECTED
            assert all(grant in node['execution']['grants'] for grant in prior['execution']['grants'])
            for grant in node['execution']['grants']:
                if grant not in prior['execution']['grants']: assert grant['stat'] in FIELDS and grant['mode']=='flat'
        if key in OPEN: assert node['standard_graph'] and node['execution']['status']=='full' and prior['execution']['status']!='full'
        if key in MIXED: assert node['execution']['status']=='partial' and node['execution']['unsupported']
        if key in OFFGRAPH: assert node['execution']['status']=='full' and not node['standard_graph']
    assert set(changed_nodes)==AFFECTED
    for key,node in caps['nodes'].items(): assert node['execution']==data['source_tree']['nodes'][key]['execution']
    for key,node in caps['boundaries'].items(): assert node['execution']==data['source_tree']['nodes'][key]['execution']
    assert set(caps['mastery_boundaries'])=={'34383','7137','61283','1727'}
    for effect,entry in caps['mastery_boundaries'].items():
        assert entry['execution']['status']=='unsupported'
        for host in entry['host_nodes']:
            actual=next(x for x in data['source_tree']['nodes'][host]['mastery_choices'] if x['effect']==entry['effect'])
            assert actual['execution']==entry['execution'] and actual['stats']==entry['source_lines']
    page=Page();page.feed((REF/'index.html').read_text())
    rendered={'base-cap':.75,'safety-cap':.83,'save-version':36}
    expected={'default_75':(1,.75,.75,25),'raw_40_cap_83':(.4,.83,.4,60),'raw_75_cap_83':(.75,.83,.75,25),'raw_83_cap_83':(.83,.83,.83,17),'raw_100_cap_83':(1,.83,.83,17),'safety_ceiling':(1,.83,.83,17)}
    for key,(raw,cap,effective,damage) in expected.items():
        ex=caps['examples'][key];p=ex['profile'];assert p['ok']
        for element in ['fire','cold','lightning']:
            near(p['raw_resistances'][element],raw);near(p['maximum_resistances'][element],cap);near(p['effective_resistances'][element],effective)
            near(ex['hits'][element]['damage_total'],damage)
            rendered[key+'-'+element+'-hit']=ex['hits'][element]['damage_total']
        near(ex['fire_burn']['damage_total'],damage)
        rendered.update({key+'-raw':raw,key+'-maximum':cap,key+'-effective':effective,key+'-burn':ex['fire_burn']['damage_total']})
    route=caps['reachable_build'];assert route['whole_build_valid'] and route['save_attempts']==0 and route['level']==69 and route['points_spent']==73
    assert len(route['allocated'])==len(set(route['allocated']))==74 and OPEN<=set(route['allocated'])
    assert route['allocated'][0]=='47175'
    allocated={route['allocated'][0]}
    for node in route['allocated'][1:]:
        assert allocated.intersection(data['source_tree']['nodes'][node]['neighbors']),node
        allocated.add(node)
    rendered.update({'route-level':69,'route-points':73})
    for element,raw in [('fire',.91),('cold',.83),('lightning',.83)]:
        p=route['profile'];near(p['raw_resistances'][element],raw);near(p['maximum_resistances'][element],.83);near(p['effective_resistances'][element],.83)
        rendered.update({'route-'+element+'-raw':raw,'route-'+element+'-maximum':.83,'route-'+element+'-effective':.83})
    equipment=caps['equipment'];near(equipment['base_raw_fire'],.15);near(equipment['affix_max_raw_fire'],.25);near(equipment['maximum_raw_fire'],.4)
    assert equipment['equipment_cold_sources']==equipment['equipment_lightning_sources']==[]
    rendered.update({'equipment-base-fire':.15,'equipment-affix-fire':.25,'equipment-total-fire':.4})
    assert page.values.keys()==rendered.keys()
    for key,value in rendered.items():near(page.values[key],value)
    assert len(page.ids)==len(set(page.ids))
    for target in page.links:
        if target.startswith('#'): assert target[1:] in page.ids,target
        elif target and not target.startswith(('https://','http://','mailto:')): assert (REF/target.split('#')[0]).exists(),target
    for asset in page.assets: assert asset and not asset.startswith(('http:','https:')) and (REF/asset).exists(),asset
    # Projection only: restore exactly bounded display, source-policy, zero-stat and version changes.
    approved=[];projection=deepcopy(data)
    for kind,path,before,after in differences(old,data):
        category=None
        if kind=='added' and path==('elemental_resistance_caps',):category='new_cap_examples'
        elif kind=='added' and path[-1] in FIELDS and path[-2] in ['stats','default_stats','defense_stats'] and after==0:category='new_zero_stat'
        elif before==35 and after==36 and path[-1] in ['version','save_version','schema']:category='version'
        elif path==('game_version',) and before=='0.58.0' and after=='0.59.0':category='version'
        elif path[0]=='source_tree' and path[1]=='nodes' and path[2] in AFFECTED and path[3]=='execution':category='source_execution'
        elif path[:2]==('source_tree_localization','nodes') and path[2] in AFFECTED and path[3]=='stats':category='dynamic_localization'
        elif path[:2]==('source_tree_localization','lines') and data['source_tree_localization']['lines'][path[2]]['status']['grants'] and all(g['stat'] in FIELDS for g in data['source_tree_localization']['lines'][path[2]]['status']['grants']):category='dynamic_localization'
        elif path[-1]=='description' and (path[:2] in [('equipment','emberhide_vest'),('defenses','fire_resistance')] or path==('monster_attacks','locked_circle','example','armor_definition','description') or path[:4]==('town_maps','stock','equipment_merchant',12)):
            assert '83%' in after;category='cap_display_text'
        assert category is not None,(kind,path,before,after)
        at=projection
        for part in path[:-1]:at=at[part]
        if kind=='added':del at[path[-1]]
        else:at[path[-1]]=before
        approved.append({'kind':kind,'path':list(path),'category':category,'before':before,'after_sha256':digest(after)})
    assert projection==old and digest(projection)==digest(old)
    baseline=json.loads((QA/'v058-art-baseline.json').read_text())
    for group,expected_count in [('asset_pngs',61),('reference_pngs',68)]:
        assert len(baseline[group])==expected_count
        assert {p:sha(ROOT/p) for p in baseline[group]}==baseline[group]
    report={'passed':True,'baseline_commit':BASE,'numeric_decode':'Both catalog JSON documents decoded with parse_int=float and parse_float=float; object keys canonicalized for hash',
            'old_catalog_semantic_sha256':digest(old),'current_catalog_semantic_sha256':digest(data),'projected_catalog_semantic_sha256':digest(projection),
            'old_asset_pngs_unchanged':61,'old_reference_pngs_unchanged':68,'changed_source_nodes':sorted(changed_nodes),'new_complete_standard_nodes':sorted(OPEN),
            'rendered_authoritative_values_checked':len(rendered),'all_html_anchor_and_local_asset_links_valid':True,'approved_changes':approved}
    save('v058-projection-preservation.json',report)
    print(json.dumps({k:v for k,v in report.items() if k!='approved_changes'},ensure_ascii=False,indent=2))


if __name__=='__main__':main()

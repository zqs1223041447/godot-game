#!/usr/bin/env python3
"""Focused v75 source-stat reference verification and exact v74 preservation."""
from copy import deepcopy
import hashlib,json,math
from html.parser import HTMLParser
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3];QA=Path(__file__).resolve().parent;REF=ROOT/'docs/reference'
def sha(raw):return hashlib.sha256(raw).hexdigest()
def digest(value):return sha(json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode())
def near(a,b):assert math.isfinite(a) and abs(a-b)<=max(1e-9,abs(b)*1e-10),(a,b)
class Page(HTMLParser):
    def __init__(self):super().__init__();self.ids=[];self.links=[];self.assets=[];self.values={};self.labels={};self.active=None
    def handle_starttag(self,tag,attrs):
        attrs=dict(attrs)
        if 'id' in attrs:self.ids.append(attrs['id'])
        if 'href' in attrs:self.links.append(attrs['href'])
        if 'src' in attrs:self.assets.append(attrs['src'])
        if 'data-source-damage-life-value' in attrs:
            key=attrs['data-source-damage-life-value'];assert key not in self.values
            self.values[key]=float(attrs['data-value']);self.labels[key]='';self.active=key
    def handle_data(self,text):
        if self.active:self.labels[self.active]+=text
    def handle_endtag(self,tag):
        if tag=='strong':self.active=None

def main():
    baseline=json.loads((QA/'v074-baseline.json').read_text());data=json.loads((REF/'catalog.json').read_text());rule=data['source_monster_damage_life']
    assert data['game_version']=='0.75.0' and data['save_version']==rule['save_version']==47
    assert rule['equipment_vocabulary']==46 and rule['source_policy']==45
    assert set(data)==set(baseline['top_level_sha256'])|{'source_monster_damage_life'}
    preserved=[]
    for key,expected in baseline['top_level_sha256'].items():
        if key not in ['game_version','mechanisms','source_monster_movement']:
            assert digest(data[key])==expected,key;preserved.append(key)
    changed_movement={'current_definition_count','current_pool'}
    for key,expected in baseline['movement_fields_sha256'].items():
        if key not in changed_movement:assert digest(data['source_monster_movement'][key])==expected,'movement.'+key
    assert set(data['source_monster_movement'])-set(baseline['movement_fields_sha256'])=={'stride_pool','legacy_roll_policy','stride_roll_policy','current_roll_policy'}
    assert len(baseline['mechanisms'])==24 and len(data['mechanisms'])==26
    assert rule['legacy_definition_count']==23 and rule['current_source_definition_count']==3 and rule['current_definition_count']==26
    for key,old in baseline['mechanisms'].items():assert digest(data['mechanisms'][key])==digest(old),key
    new_ids={'source_ember_power','source_grove_vitality'};assert set(data['mechanisms'])-set(baseline['mechanisms'])==new_ids
    assert set(rule['bindings'])==new_ids
    expected_bindings={'source_ember_power':('13219',0,'10% increased Damage','global_increased',.1),'source_grove_vitality':('52282',0,'5% increased maximum Life','max_health',.05)}
    rendered={'current-count':(26,False),'legacy-count':(23,False),'source-count':(3,False),'save-version':(47,False),'vocabulary':(46,False),'source-policy':(45,False)}
    for key,(node,index,line,stat,amount) in expected_bindings.items():
        binding=rule['bindings'][key];entry=binding['source_entry'];definition=binding['definition'];effect=binding['source_effect'];tree=data['source_tree']
        assert entry['node_id']==node and entry['stat_index']==index and entry['raw_line']==line
        assert tree['nodes'][node]['stats'][index]==line
        for a,b in [('source_hash','source_sha256'),('source_version','source_version'),('source_commit','source_commit')]:assert entry[a]==tree[b]
        assert entry['source_url']=='https://raw.githubusercontent.com/grindinggear/skilltree-export/'+tree['source_commit']+'/data.json'
        assert effect['supported'] and effect['grants']==[{'stat':stat,'mode':'increased','value':amount}]
        assert definition['typed_grants']==effect['grants'] and definition['source_refs']==[entry] and definition['source_entry']==entry
        assert definition['source_line']==line and definition['source_policy']==definition['source_save_version']==45
        expected_stats={'global_increased':.1} if stat=='global_increased' else {}
        expected_capacity={} if stat=='global_increased' else {'max_health':.05}
        assert definition['stats']==expected_stats and definition.get('capacity_increased',{})==expected_capacity
        for actor in ['player','monster']:
            grant=binding[actor+'_grant'];assert grant['ok'] and not grant['errors'] and grant['actor']==actor
            assert grant['role_coefficient']==1 and grant['stats']==expected_stats and grant.get('capacity_increased',{})==expected_capacity
            assert grant['source_grants']==[definition] and grant['mechanism_ids']==[key]
        mechanism=data['mechanisms'][key]
        for k,v in definition.items():assert mechanism[k]==v,(key,k)
        assert mechanism['source_refs']==[entry] and mechanism['supported_actors']==['player','monster']
        assert binding['legacy_grant']['stats']==baseline['mechanisms'][binding['legacy_id']]['stats']
        rendered.update({key+'-increase':(amount,True),key+'-coefficient':(1,False),key+'-legacy-flat':(next(iter(binding['legacy_grant']['stats'].values())),False)})
    assert data['mechanisms']['source_grove_vitality']['description']=='最大生命提高 5.0%'
    legacy=['ember_power','gale_stride','grove_vitality','aegis_capacity','aegis_recovery'];stride=legacy.copy();stride[1]='source_gale_stride';current=stride.copy();current[0]='source_ember_power';current[2]='source_grove_vitality'
    for chapter in [rule,data['source_monster_movement']]:
        assert chapter['legacy_pool']==legacy and chapter['stride_pool']==stride and chapter['current_pool']==current
        assert chapter['legacy_roll_policy']=='legacy_flat_v1' and chapter['stride_roll_policy']=='source_stride_v1' and chapter['current_roll_policy']=='source_damage_life_v2'
        assert chapter['current_definition_count']==26
    assert not rule['legacy_player_only_rejection']['ok'] and rule['legacy_player_only_rejection']['stats']=={}
    assert any('Player-only mechanism poe_global_damage' in e for e in rule['legacy_player_only_rejection']['errors'])
    assert [(r['wave'],r['template_id']) for r in rule['budget']]==[(wave,template) for wave in [1,6,10,15] for template in ['crawler','skitter','brute']]
    ember=rule['bindings']['source_ember_power'];grove=rule['bindings']['source_grove_vitality']
    for row in rule['budget']:
        base=row['base'];sp=row['species'];tier=row['rarity_multipliers'];wave=row['wave'];prefix=str(wave)+'-'+row['template_id']
        near(base['health'],sp['health']*(1+(wave-1)*.16)*tier['health']);near(base['damage'],(sp['damage']+(wave-1)*.7)*tier['damage'])
        near(row['legacy_life']['health'],base['health']+grove['legacy_grant']['stats']['max_health'])
        near(row['current_life']['health'],base['health']*(1+grove['monster_grant']['capacity_increased']['max_health']))
        near(row['legacy_damage']['damage'],base['damage']+ember['legacy_grant']['stats']['damage'])
        near(row['current_damage']['damage'],base['damage']*(1+ember['monster_grant']['stats']['global_increased']))
        near(row['life_delta'],row['current_life']['health']-row['legacy_life']['health']);near(row['damage_delta'],row['current_damage']['damage']-row['legacy_damage']['damage'])
        variants=['base','legacy_life','current_life','legacy_damage','current_damage'];unchanged=[]
        for v in variants:
            enemy=row[v];assert enemy['template_id']==row['template_id'] and enemy['wave']==wave and enemy['rarity']==row['rarity'] and enemy['reward_eligible']
            assert row['rarity']==('magic' if wave==1 else 'rare')
            if v!='base':assert len(enemy['mechanism_ids'])==1
            clean=deepcopy(enemy)
            for field in ['health','max_health','damage','mechanism_ids','mechanism_stats','mechanism_policy','mechanism_source_grants']:clean.pop(field,None)
            unchanged.append(clean)
        assert all(v==unchanged[0] for v in unchanged)
        for key,amount in [('base-life',base['health']),('old-life',row['legacy_life']['health']),('current-life',row['current_life']['health']),('base-damage',base['damage']),('old-damage',row['legacy_damage']['damage']),('current-damage',row['current_damage']['damage'])]:rendered[prefix+'-'+key]=(amount,False)
    selected={(r['wave'],r['template_id']):r for r in rule['budget']}
    for key,expected in { (1,'skitter'):(42.65,40.6875,9.268,9.68),(6,'brute'):(431.4,448.875,26.268,28.38),(10,'brute'):(583.4,608.475,29.628,32.076)}.items():
        row=selected[key]
        for actual,want in zip([row['legacy_life']['health'],row['current_life']['health'],row['legacy_damage']['damage'],row['current_damage']['damage']],expected):near(actual,want)
    mixed=rule['mixed_fixed_before_increased'];near(mixed['life']['health'],(mixed['base']['health']+grove['legacy_grant']['stats']['max_health'])*1.05);near(mixed['damage']['damage'],(mixed['base']['damage']+ember['legacy_grant']['stats']['damage'])*1.1)
    for k,v in [('mixed-base-life',mixed['base']['health']),('mixed-life',mixed['life']['health']),('mixed-base-damage',mixed['base']['damage']),('mixed-damage',mixed['damage']['damage'])]:rendered[k]=(v,False)
    for path,expected in baseline['preserved_files'].items():assert sha((ROOT/path).read_bytes())==expected,path
    old_pngs={p for p in baseline['preserved_files'] if p.endswith('.png')};actual_pngs={str(p.relative_to(ROOT)) for folder in [ROOT/'assets',ROOT/'data',REF] for p in folder.rglob('*.png')};assert old_pngs==actual_pngs
    html=(REF/'index.html').read_text();page=Page();page.feed(html);assert len(page.ids)==len(set(page.ids))
    assert set(baseline['old_html_anchors'])<=set(page.ids)
    added=set(page.ids)-set(baseline['old_html_anchors']);assert added=={'mechanisms-source_ember_power','mechanisms-source_grove_vitality','rules-source_monster_damage_life'}
    assert page.values.keys()==rendered.keys(),(page.values.keys()-rendered.keys(),rendered.keys()-page.values.keys())
    for key,(amount,is_percent) in rendered.items():near(page.values[key],amount);assert page.labels[key].strip()==format(amount*(100 if is_percent else 1),'g')+('%' if is_percent else ''),key
    for link in page.links:
        if link.startswith('#'):assert link[1:] in page.ids,link
        elif link and not link.startswith(('http:','https:','mailto:')):assert (REF/link.split('#')[0]).is_file(),link
    for asset in page.assets:assert not asset.startswith(('http:','https:')) and (REF/asset).is_file(),asset
    for text in ['23条历史定义','三条当前单条源绑定','当前共26条定义','不表示所有源基石均已共享','最大生命提高 5.0%','source_stride_v1','source_damage_life_v2','Body Transfiguration','蓝怪不同时持有两个词缀','不是DPS','每帧不重新解析']:assert text in html,text
    for text in ['当前唯一源绑定','本批仅有这一条当前源绑定','第24条']:assert text not in html,text
    report={'passed':True,'baseline_commit':'f2427f3','historical_catalog_sections_preserved':preserved,'legacy_definitions_preserved':23,'old_source_gale_definition_preserved':True,'old_movement_budget_preserved':True,'new_source_bindings':2,'current_source_bindings':3,'total_definitions':26,'budget_rows_from_catalog':len(rule['budget']),'fixed_before_increased_cases':2,'authoritative_html_values_and_labels_checked':len(rendered),'preserved_files':len(baseline['preserved_files']),'old_pngs_preserved':len(old_pngs),'new_art_files':0,'old_html_anchors_preserved':len(baseline['old_html_anchors']),'new_html_anchors':sorted(added),'source_coverage_byte_identical':True,'all_anchor_and_local_file_links_valid':True,'save_version':47,'equipment_vocabulary':46,'source_policy':45,'catalog_sha256':sha((REF/'catalog.json').read_bytes()),'html_sha256':sha((REF/'index.html').read_bytes()),'scope':'Narrow runtime fragment only; preserve historical catalog bytes/types; deterministic HTML and focused new-source/preservation checks. No full export, historical combat suites, import, browser/UI, native launch, artwork or packaging.'}
    with (QA/'v074-preservation.json').open('x') as f:json.dump(report,f,ensure_ascii=False,indent=2);f.write('\n')
    print(json.dumps(report,ensure_ascii=False,indent=2))
if __name__=='__main__':main()

#!/usr/bin/env python3
"""Offline deliverable checks: exhaustive links/assets, geometry, no network dependencies."""
import importlib.util
import json
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
REF=ROOT/'docs/reference'
class Inspector(HTMLParser):
    def __init__(self):
        super().__init__(); self.ids=[]; self.links=[]; self.assets=[]; self.viewbox=None; self.node_ids=[]; self.trace_values={}; self.weapon_values={}; self.pierce_hits={}; self.craft_values={}; self.telegraph_values={}; self.encounter_values={}; self.flask_values={}
    def handle_starttag(self,tag,attrs):
        a=dict(attrs)
        if 'id' in a:self.ids.append(a['id'])
        if tag=='a':self.links.append(a.get('href',''))
        if tag in ['img','script','link']:
            url=a.get('src',a.get('href',''))
            if url:self.assets.append(url)
        if tag=='svg' and a.get('id')=='passive-map':self.viewbox=list(map(float,a['viewbox'].split()))
        if 'data-node' in a:self.node_ids.append(a['data-node'])
        if 'data-pierce-hits' in a:self.pierce_hits[a['data-pierce-hits']]=int(a['data-value'])
        if 'data-encounter-value' in a:self.encounter_values[a['data-encounter-value']]=float(a['data-value'])
        if 'data-flask-value' in a:self.flask_values[a['data-flask-value']]=float(a['data-value'])
        if 'data-telegraph-value' in a:self.telegraph_values[a['data-telegraph-value']]=float(a['data-value'])
        if 'data-craft-value' in a:self.craft_values[a['data-craft-value']]=int(a['data-value'])
        if 'data-weapon-trace' in a:self.weapon_values[a['data-weapon-trace']]=float(a['data-value'])
        if 'data-trace-value' in a:self.trace_values[a['data-trace-value']]=float(a['data-value'])

def main():
    source=(REF/'index.html').read_text()
    inspector=Inspector(); inspector.feed(source)
    data=json.loads((REF/'catalog.json').read_text())
    expected_encounters={}
    for key,definition in data['encounters'].items():
        for template,sample in definition['examples'].items():
            expected_encounters[key+'-'+template+'-常规']=sample['before'][definition['field']]
            expected_encounters[key+'-'+template+'-挑战']=sample['after'][definition['field']]
    assert inspector.encounter_values==expected_encounters, 'Challenge chart differs from the production compiler'
    expected_telegraphs={}
    for key,attack in data['monster_attacks'].items():
        example=attack['example']; cases=example['cases']; p=attack['profile']
        values={'radius':p['radius'],'warning':p['windup_seconds'],'recovery':p['recovery_seconds'],'standing':cases['standing']['settlement']['damage_total'],'armored':cases['armored']['settlement']['damage_total'],'moving':0.0}
        expected_telegraphs.update({key+'-'+field:value for field,value in values.items()})
        assert not cases['moving']['inside'] and not cases['moving']['settlement'], 'Dodge example must have no synthetic damage settlement'
    assert inspector.telegraph_values==expected_telegraphs, 'Telegraph diagram diverges from real event and settlement'
    expected_flasks={f'{key}-time-{i}':r['resource'] for key,f in data.get('flasks',{}).items() for i,r in enumerate(f['example']['rows'])}
    assert inspector.flask_values==expected_flasks, 'Flask recovery table differs from actual runtime'
    expected_craft={}
    for operation in [key for key, entry in data['crafting'].items() if entry['kind']=='operation']:
        sample=data['crafting'][operation]['example']
        quoted=sample['quote']
        expected_craft[operation+'-amount']=(quoted['materials'] if operation=='salvage' else quoted['cost'])['calibration_shard']
        expected_craft[operation+'-before']=sample['balance_before']
        expected_craft[operation+'-after']=sample['balance_after']
    assert inspector.craft_values==expected_craft, 'Crafting flow does not match the authoritative plans'
    assert inspector.pierce_hits == {f'{skill}-{mode}':len(sample['observed_hits']) for skill,pair in data['projectile_support_examples']['skills'].items() for mode,sample in pair.items()}, 'Pierce diagram differs from actual collision events'
    assert not [x for x,n in Counter(inspector.ids).items() if n>1], 'Duplicate document IDs'
    assert not [x for x in inspector.links if x.startswith('#') and x[1:] not in inspector.ids], 'Broken internal links'
    assert not [x for x in inspector.assets if '://' in x or x.startswith('//')], 'Network-dependent resource'
    for href in inspector.links:
        if href and not href.startswith(('#','https://','http://')):
            assert (REF/href.split('#',1)[0]).is_file(), 'Missing local evidence link '+href
    for asset in inspector.assets:assert (REF/asset).is_file(), 'Missing asset '+asset
    for cat in ['skills','supports','equipment','affixes','fixed_items','jewels','jewel_affixes','passives','mechanisms','weapon_stages','defenses','crafting','monsters','monster_attacks','encounters']:
        for key in data[cat]:assert f'{cat}-{key}' in inspector.ids, 'Unbrowsable entry '+key
    trace=data['defenses']['fire_resistance']['worked_example']['trace']
    expected={'input_total':sum(trace['raw_components'].values()), **{k:trace[k] for k in ['damage_total','shield_spent','health_lost']}}
    assert inspector.trace_values==expected, 'Defense diagram diverges from production trace'
    local=data['weapon_stages']['weapon_local']; sample=local['examples']['local_max']; hit=sample['hits']['parent']; assembly=hit['packet']['assembly']; weapon=assembly['weapon']; profile=weapon['profile']
    expected_weapon={'P':profile['base']['physical'],'F':profile['flat']['physical'],'L':profile['increased']['physical'],'W':weapon['components']['physical'], 'resolved':hit['resolved']['total'],'known_target':hit['known_target_resolved']['total'],'health_lost':hit['known_target_settlement']['health_lost']}
    for prefix,components in [('intrinsic',assembly['intrinsic']),('weapon',weapon['contribution']),('added',assembly['added']),('raw',hit['packet']['base'])]:
        expected_weapon.update({prefix+'_'+key:amount for key,amount in components.items()})
    assert inspector.weapon_values==expected_weapon, 'Weapon diagram diverges from actual assembly/settlement'
    assert '../benchmarks/v0.13-weapon-budget-report.md' in inspector.links and '../benchmarks/v0.13-weapon-budget-replay.json' in inspector.links
    assert '75% 火抗未来压力目标' in source and '+25.39%' in source, 'Budget must disclose future-target exception'
    assert 'skills-basic' not in inspector.ids and '#skills-basic' not in inspector.links, 'Basic attack must not invent an additional active skill'
    assert '#rules-basic_attack' in inspector.links and '#weapon_stages-weapon_local' in inspector.links
    assert len(data['skills'])==10 and len(data['equipment'])==14 and len(data['affixes'])==26
    assert data['canonical']['support_slots']==5 and data['canonical']['base_skill_groups']==10 and len(data['canonical']['slots'])==9
    assert len(data['source_tree']['nodes'])==3390 and len(data['source_tree']['edges'])==2697
    for key in data['source_tree']['nodes']: assert f'source_passives-{key}' in inspector.ids, 'Unbrowsable source node '+key
    assert '旧181节点研究' in source and '灰色锁定' in source and '未完整执行的节点不可分配' in source
    for key in ['whetstone_edge','tempered_edge']:
        assert data['affixes'][key]['affected_skills']==['tornado'] and data['affixes'][key]['other_consumers']==['basic']
    assert data['current_loot_profile_id']=='canonical_v14' and [p['weight'] for p in data['current_loot_profile']]==[30,20,10,10,30]
    assert [p['weight'] for p in data['loot_profiles']['v0.13']]==[45,25,15,15]
    assert [p['weight'] for p in data['loot_profiles']['v0.11']]==[60,25,15]
    assert '每次已产生的装备奖励' in source and '不新增奖励分支' in source
    assert '没有隐含的武器本地伤害阶段' not in source and '本地武器伤害/攻速阶段' not in source
    assert data['fire_encounter']['balance_source']=='original_game_balance'
    assert data['defenses']['fire_resistance']['origin']=='original'
    assert '已知目标' in source and '防御前' in source and '抗性后' in source
    assert 'expansion_loot_percent' not in data['limits'], 'Old two-pool odds presented as current natural loot'
    assert set(inspector.node_ids)==set(data['passives']), 'Tree omits a runtime node'
    x,y,w,h=inspector.viewbox
    for node in data['passives'].values():
        nx,ny=node['position'];assert x+19<=nx<=x+w-19 and y+19<=ny<=y+h-19, 'Tree clips node'
    for sample in data['special_coverage'].values():
        for s in sample['connected']['active_sources'].values():
            cx,cy=s['position'];r=s['radius'];assert x<=cx-r and cx+r<=x+w and y<=cy-r and cy+r<=y+h, 'Tree clips coverage circle'
    script=(REF/'reference.js').read_text()
    for unsupported in ['fetch(', 'XMLHttpRequest', 'import(', 'localStorage', 'sessionStorage']:
        assert unsupported not in script, 'Offline script includes external/persistent dependency '+unsupported
    assert 'font-size:16px' in (REF/'reference.css').read_text()
    spec=importlib.util.spec_from_file_location('generator',ROOT/'tools/build_reference.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    art=json.loads((REF/'art/manifest.json').read_text())
    assert art['status']=='complete' and art['written_images']==64 and len(art['entries'])==64
    expected_art={(cat,key) for cat in ['skills','supports','equipment','fixed_items','jewels','monsters'] for key in data[cat]}
    expected_art.update(('flasks',key) for key in data.get('flasks',{}))
    actual_art={(('fixed_items' if row.get('entry_type')=='fixed_item' else row['category']),row['id']) for row in art['entries']}
    assert actual_art==expected_art, 'Art manifest omits or adds runtime entries'
    assert len(inspector.assets)==len(art['entries']), 'Runtime artwork missing from an entry'
    assert module.build(data,art)==source, 'Generated HTML is stale'
    assert module.build(data,art)==module.build(data,art), 'Nondeterministic generator'
    print(f'Reference catalog: {len(inspector.ids)} unique anchors, {len(inspector.links)} links, {len(inspector.assets)} local images; complete geometry and deterministic HTML passed')
if __name__=='__main__':main()

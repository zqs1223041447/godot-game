#!/usr/bin/env python3
"""Offline deliverable checks: exhaustive links/assets, geometry, no network dependencies."""
import importlib.util
import hashlib
import json
import re
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
REF=ROOT/'docs/reference'
class Inspector(HTMLParser):
    def __init__(self):
        super().__init__(); self.ids=[]; self.links=[]; self.assets=[]; self.viewbox=None; self.node_ids=[]; self.trace_values={}; self.weapon_values={}; self.pierce_hits={}; self.craft_values={}; self.telegraph_values={}; self.encounter_values={}; self.flask_values={}; self.ember_values={}; self.sunwell_values={}; self.sunwell_obstacles={}; self.entry_id=None; self.entry_images=[]
    def handle_starttag(self,tag,attrs):
        a=dict(attrs)
        if tag=='article':self.entry_id=a.get('id')
        if 'id' in a:self.ids.append(a['id'])
        if tag=='a':self.links.append(a.get('href',''))
        if tag in ['img','script','link']:
            url=a.get('src',a.get('href',''))
            if url:self.assets.append(url)
            if tag=='img':self.entry_images.append((self.entry_id,url))
        if tag=='svg' and a.get('id')=='passive-map':self.viewbox=list(map(float,a['viewbox'].split()))
        if 'data-node' in a:self.node_ids.append(a['data-node'])
        if 'data-pierce-hits' in a:self.pierce_hits[a['data-pierce-hits']]=int(a['data-value'])
        if 'data-encounter-value' in a:self.encounter_values[a['data-encounter-value']]=float(a['data-value'])
        if 'data-flask-value' in a:self.flask_values[a['data-flask-value']]=float(a['data-value'])
        if 'data-telegraph-value' in a:self.telegraph_values[a['data-telegraph-value']]=float(a['data-value'])
        if 'data-craft-value' in a:self.craft_values[a['data-craft-value']]=int(a['data-value'])
        if 'data-weapon-trace' in a:self.weapon_values[a['data-weapon-trace']]=float(a['data-value'])
        if 'data-trace-value' in a:self.trace_values[a['data-trace-value']]=float(a['data-value'])
        if 'data-ember-value' in a:self.ember_values[a['data-ember-value']]=float(a['data-value'])
        if 'data-sunwell-value' in a:
            assert a['data-sunwell-value'] not in self.sunwell_values, 'Duplicate Sunwell numeric evidence'
            self.sunwell_values[a['data-sunwell-value']]=float(a['data-value'])
        if 'data-sunwell-obstacle' in a:
            assert self.entry_id=='maps-sunwell_terrace' and tag=='rect'
            self.sunwell_obstacles[int(a['data-sunwell-obstacle'])]={k:float(a[k]) for k in ['x','y','width','height']}

    def handle_endtag(self,tag):
        if tag=='article':self.entry_id=None

def canonical_hash(value):
    return hashlib.sha256(json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()

def check_sunwell(data,source,inspector):
    baseline=json.loads((ROOT/'docs/qa/v048-reference/reference-baseline.json').read_text())
    assert data['game_version']=='0.48.0' and data['save_version']==30
    map_ids={m['id'] for m in data['town_maps']['options']['maps']}
    assert map_ids=={'old_garden','broken_ruins','sunwell_terrace'}
    assert set(data['map_camps'])==set(data['map_bosses'])==map_ids
    assert len(data['normal_journey']['tiers'])==9 and set(data['normal_journey']['initial_journey']['best_tiers'])==map_ids
    for key,saved in baseline['legacy_maps'].items():
        parts={'catalog_map':next(m for m in data['town_maps']['options']['maps'] if m['id']==key),
            'town_example':data['town_maps']['examples'][key], 'camps':data['map_camps'][key],
            'boss':data['map_bosses'][key], 'normal_tiers':[m for m in data['normal_journey']['tiers'] if m['id']==key]}
        for name,value in parts.items():assert canonical_hash(value)==saved[name], 'Legacy map structure changed: '+key+'/'+name
        article=re.search(r'<article\b[^>]*\bid="maps-'+key+r'"[^>]*>.*?</article>',source,re.S).group()
        assert hashlib.sha256(article.encode()).hexdigest()==saved['article_sha256'], 'Legacy map article changed: '+key
    pngs={p.relative_to(ROOT).as_posix() for p in REF.rglob('*.png')}
    assert pngs=={p for p in baseline['preserved_files'] if p.endswith('.png')}, 'Reference PNG inventory changed'
    for name,saved in baseline['preserved_files'].items():
        content=(ROOT/name).read_bytes()
        assert len(content)==saved['bytes'] and hashlib.sha256(content).hexdigest()==saved['sha256'], 'Reference artwork changed: '+name
    assert canonical_hash(data['monster_attacks'])==baseline['monster_attacks'], 'Default telegraphs must not inherit the new sequence'
    assert all(attack['max_events_per_attack']==1 for attack in data['monster_attacks'].values())
    key='sunwell_terrace';sunwell=data[key];boss=data['map_bosses'][key];sequence=boss['sequence'];d=boss['definition']
    assert sunwell['save_version']==30 and 'maps-'+key in inspector.ids
    assert d['id']=='sunwell_echo' and d['target_rule']=='player_at_start'
    assert sequence['pulse_count']==2 and sequence['normalized_deadlines']==[0.8,1.6]
    assert sequence['pulse_interval']==0.8 and d['profile']['radius']==85 and d['profile']['damage_multiplier']==0.65
    assert sequence['base_recovery_seconds']==1.9 and abs(sequence['total_contact_multiplier']-1.3)<1e-9
    assert sequence['default_profile_max_events']==1 and sequence['complete_after_recovery']
    assert sequence['recovery_state']['phase']=='recovery' and sequence['recovery_state']['pulses_emitted']==2
    policy=boss['policy'];limits=data['monster_attacks']['locked_circle']['limits']['recovery_seconds']
    expected_recovery=min(limits['maximum'],max(limits['minimum'],sequence['base_recovery_seconds']*policy['base_attack_speed']/max(policy['minimum_attack_speed'],sequence['source_attack_speed'])))
    assert abs(sequence['actual_recovery_seconds']-expected_recovery)<1e-9
    expected={'warning':d['profile']['windup_seconds'],'pulse-count':sequence['pulse_count'],
        'pulse-interval':sequence['pulse_interval'],'per-pulse-multiplier':d['profile']['damage_multiplier'],
        'total-multiplier':sequence['total_contact_multiplier'],'attack-radius':d['profile']['radius'],
        'player-radius':boss['player_radius'],'clear-center-distance':d['profile']['radius']+boss['player_radius'],
        'base-recovery':sequence['base_recovery_seconds'],'attack-speed':sequence['source_attack_speed'],
        'actual-recovery':sequence['actual_recovery_seconds']}
    assert sequence['pulses'][0]['event']==boss['event'] and len(sequence['pulses'])==2
    clock=0
    for index,pulse in enumerate(sequence['pulses']):
        event=pulse['event'];clock+=event['step_time']
        assert event['pulse_index']==index and event['pulse_count']==sequence['pulse_count']
        assert event['attack_id']==boss['start']['attack_id'] and event['center']==sequence['locked_center']==boss['start']['center']
        assert abs(clock-pulse['normalized_deadline'])<1e-9 and abs(event['attack_age']-clock)<1e-9
        assert event['radius']==d['profile']['radius'] and event['visual_pattern']=='sunwell_echo'
        for damage_type,contact in sequence['contact_components'].items():
            assert abs(event['packet']['base'][damage_type]-contact*d['profile']['damage_multiplier'])<1e-9
        assert pulse['cases']['standing']['inside'] and not pulse['cases']['moving']['inside'] and pulse['cases']['moving']['settlement']=={}
        assert abs(pulse['cases']['moving']['position'][0]+sequence['move_speed']*clock)<1e-4
        expected['deadline-'+str(index)]=pulse['normalized_deadline'];expected['radius-'+str(index)]=event['radius']
    camps=data['map_camps'][key]['camps'];geometry=data['town_maps']['examples'][key]['geometry'];origin=geometry['bounds']['position']
    assert [c['name'] for c in camps]==['西泉据点','北门据点','东阶据点'] and [c['root_count'] for c in camps]==[12,12,12]
    assert geometry['obstacle_style']=='spring_basin' and len(geometry['walls'])==4
    for index,wall in enumerate(geometry['walls']):
        assert inspector.sunwell_obstacles[index]=={'x':wall['position'][0]-origin[0],'y':wall['position'][1]-origin[1],'width':wall['size'][0],'height':wall['size'][1]}
    assert len(inspector.sunwell_obstacles)==len(geometry['walls'])
    expected.update({'camp-count':len(camps),'camp-roots':camps[0]['root_count'],'total-roots':sum(c['root_count'] for c in camps),
        'trigger-radius':camps[0]['trigger_radius'],'spawn-seconds':sunwell['spawn_seconds'],'player-clearance':sunwell['player_clearance'],
        'save-version':sunwell['save_version'],'frost-min-wave':sunwell['elemental_gates']['frost_guard']['minimum_wave'],
        'storm-min-wave':sunwell['elemental_gates']['storm_skitter']['minimum_wave'],'obstacle-count':len(geometry['walls'])})
    assert [r['base']['wave'] for r in sunwell['tiers']]==[3,6,10]
    assert [r['base']['fee'] for r in sunwell['tiers']]==[0,4,8] and [r['base']['completion_reward'] for r in sunwell['tiers']]==[4,8,12]
    for row in sunwell['tiers']:
        base=row['base'];maximum=row['maximum_bonus_example'];tier=base['journey_tier']
        assert base in data['normal_journey']['tiers'] and base['ordinary_target']==36
        expected_bonus=len(maximum['normal_ids'])+2*len(maximum['special_ids'])
        assert maximum['completion_reward']-base['completion_reward']==expected_bonus
        expected.update({f'tier-{tier}-wave':base['wave'],f'tier-{tier}-fee':base['fee'],f'tier-{tier}-reward':base['completion_reward'],f'tier-{tier}-max-bonus':expected_bonus})
        for camp in camps:
            pattern=sunwell['patterns'][camp['id']];actual=sunwell['roster_examples_by_wave'][str(base['wave'])][camp['id']]
            expected_templates=[]
            for ordinal in range(camp['root_count']):
                template=pattern[ordinal%len(pattern)];gate=sunwell['elemental_gates'].get(template)
                expected_templates.append(gate['source_template'] if gate and base['wave']<gate['minimum_wave'] else template)
            assert actual==expected_templates
    migration=sunwell['migration_example']
    assert migration['from_version']==29 and migration['to_version']==30 and migration['items_preserved'] and migration['currencies_preserved']
    assert migration['after_best_tiers']=={**migration['before_best_tiers'],'sunwell_terrace':0}
    assert inspector.sunwell_values==expected, 'Sunwell HTML diverges from production geometry, sequence, roster or economy'
    assert '第二响不会追踪新位置' in source and '持续离开锁点可以躲开两响' in source and '中央十字与外侧留有通路' in source
    print('Sunwell reference: 3 maps / 9 tiers, 4 solid basins, 2 locked pulses, unchanged legacy maps and 66 PNGs passed')

def main():
    source=(REF/'index.html').read_text()
    inspector=Inspector(); inspector.feed(source)
    data=json.loads((REF/'catalog.json').read_text())
    check_sunwell(data,source,inspector)
    expected_encounters={}
    for key,definition in data['encounters'].items():
        for template,sample in definition['examples'].items():
            expected_encounters[key+'-'+template+'-常规']=sample['before'][definition['field']]
            expected_encounters[key+'-'+template+'-挑战']=sample['after'][definition['field']]
    assert inspector.encounter_values==expected_encounters, 'Challenge chart differs from the production compiler'
    import re
    gem_prices={k:int(v) for k,v in re.findall(r'data-gem-trade-id="([^"]+)" data-cost="([0-9]+)"',source)}
    assert gem_prices=={o['definition_id']:o['cost'] for o in data['normal_gem_trading']['offers']}, 'Normal gem prices differ from the real catalog'
    assert data['normal_gem_trading']['recycle_credit']==1 and len(gem_prices)==len(data["skills"])+len(data["supports"])
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
    assert len(data['skills'])==10 and len(data['equipment'])==14 and len(data['affixes'])==30
    assert data['burning']['player_policy']=={'duration':3.0,'rate_fraction':0.3,'hit_multiplier':0.75,'mana_multiplier':1.2}
    assert data['burning']['enemy_budget']['total_before_defense']==28 and data['canonical']['gem_reward']['normal_frozen_definition_count']==26
    assert (REF/data['burning']['icon_file']).read_bytes()==(ROOT/'assets/ui/grimoire/ignite.png').read_bytes()
    ember=data['ember_proliferation'];policy=ember['player_policy'];spread=ember['proliferation_policy']
    assert len(data['supports'])==18 and len(data['support_program_examples'])==18
    assert policy=={'duration':3.0,'rate_fraction':0.2,'hit_multiplier':0.75,'mana_multiplier':1.3}
    assert spread=={'enabled':True,'radius':120.0,'max_targets':8,'max_hops':1,'preserves_expiry':True}
    assert ember['save_version']==29 and data['save_version']==30 and ember['mutually_exclusive_with']==['ignite']
    assert set(ember['examples'])=={'meteor','tornado'} and set(ember['incompatible_skills'])==set(data['skills'])-{'meteor','tornado'}
    assert [sample['selection'] for sample in ember['exclusive_examples']]==[['ignite','ember_proliferation'],['ember_proliferation','ignite']]
    assert all(sample['error'] for sample in ember['exclusive_examples'])
    expected_ember={**policy,**{key:spread[key] for key in ['radius','max_targets','max_hops']}}
    for skill,example in ember['examples'].items():
        profile=example['profile']
        assert {key:profile[key] for key in policy}==policy and profile['proliferation']==spread
        assert set(profile['roles'])==({'parent','child'} if skill=='tornado' else {'direct'})
        assert 'ember_proliferation' in data['skills'][skill]['compatible_supports']
        for role,values in profile['roles'].items():
            assert abs(values['dps']-values['fire_before_defense']*policy['rate_fraction'])<1e-9
            assert abs(values['total']-values['dps']*policy['duration'])<1e-9
            expected_ember.update({skill+'-'+role+'-'+field:values[field] for field in ['fire_before_defense','dps','total']})
    sample=ember['transfer_example'];original=sample['source'];inherited=sample['transfer']['burn'];recipient=sample['recipient']
    assert sample['transfer']['ok'] and inherited['raw_dps']==original['raw_dps']==recipient['raw_dps']
    assert inherited['provenance']['ember_expiry']==original['provenance']['ember_expiry']==recipient['provenance']['ember_expiry']
    assert inherited['duration']==original['provenance']['ember_expiry']-sample['transferred_at']<policy['duration']
    assert original['provenance']['ember_generation']==0 and recipient['provenance']['ember_generation']==1
    assert all(sample[key]['ok'] and sample[key]['burn']=={} and sample[key]['reason']=='spent_or_expired' for key in ['second_hop','at_expiry'])
    selection=ember['selection_example']
    assert selection['target_ids']==list(range(1,9)) and selection['over_cap_ids']==[9,10]
    assert set(selection['target_ids']).isdisjoint(selection[key] for key in ['source_id','wall_blocked_id','spawn_protected_id','dead_id','outside_radius_id'])
    migration=ember['migration_example'];quote=ember['merchant_quote']
    assert migration['from_version']==28 and migration['to_version']==29 and migration['changed_fields']==['version']
    assert migration['granted_items']==0 and migration['items_before']==migration['items_after']
    assert quote['ok'] and quote['definition_id']=='support:ember_proliferation' and quote['cost']=={'calibration_shard':4}
    assert gem_prices['support:ember_proliferation']==4 and not ember['normal_reward_pool_includes_support']
    expected_ember.update({'started_at':sample['started_at'],'transferred_at':sample['transferred_at'],'source_dps':original['raw_dps'],'transferred_dps':inherited['raw_dps'],'source_expiry':original['provenance']['ember_expiry'],'transferred_expiry':recipient['provenance']['ember_expiry'],'remaining':inherited['duration'],'merchant_cost':quote['cost']['calibration_shard'],'save_version':ember['save_version'],'granted_items':migration['granted_items']})
    assert inspector.ember_values==expected_ember, 'Ember display diverges from production policies, cast, transfer or migration'
    assert 'rules-ember_proliferation' in inspector.ids and '#rules-ember_proliferation' in inspector.links
    assert '瞬杀且未形成燃烧状态不传' in source and '不穿墙、不选出生保护目标' in source
    assert (REF/ember['icon_file']).read_bytes()==(ROOT/'assets/ui/grimoire/ember_proliferation.png').read_bytes()
    assert data['current_loot_profile_id']=='canonical_v27'
    assert data['affixes']['attack_life_leech']['formatted_ranges'][0]=={'min':'+0.20%','max':'+0.30%'}
    assert data['affixes']['global_critical_multiplier']['formatted_ranges'][2]=={'min':'+12个百分点','max':'+15个百分点'}
    assert set(data['affixes']['attack_mana_leech']['affected_skills'])=={'cleave','tornado'}
    assert data['canonical']['support_slots']==5 and data['canonical']['base_skill_groups']==10 and len(data['canonical']['slots'])==9
    assert len(data['source_tree']['nodes'])==3390 and len(data['source_tree']['edges'])==2697
    for key in data['source_tree']['nodes']: assert f'source_passives-{key}' in inspector.ids, 'Unbrowsable source node '+key
    assert '旧181节点研究' in source and '灰色锁定' in source and '未完整执行的节点不可分配' in source
    for key in ['whetstone_edge','tempered_edge']:
        assert data['affixes'][key]['affected_skills']==['tornado'] and data['affixes'][key]['other_consumers']==['basic']
    assert data['current_loot_profile_id']=='canonical_v27' and [p['weight'] for p in data['current_loot_profile']]==[30,20,10,10,30]
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
    # Exactly two retained original PNGs supplement the unchanged legacy64.
    original_art={('supports','ignite'):data['burning']['icon_file'],('supports','ember_proliferation'):ember['icon_file']}
    assert expected_art-actual_art==set(original_art) and not actual_art-expected_art, 'Only the two declared original PNGs may supplement the rendered manifest'
    actual_art.update(original_art)
    assert actual_art==expected_art, 'Art manifest omits or adds runtime entries'
    assert len(inspector.assets)==len(art['entries'])+2, 'Runtime or original artwork count differs'
    for (category,key),asset in original_art.items():
        assert inspector.assets.count(asset)==1 and inspector.entry_images.count((f'{category}-{key}',asset))==1, 'Original artwork must belong to its exact support entry'
    assert module.build(data,art)==source, 'Generated HTML is stale'
    assert module.build(data,art)==module.build(data,art), 'Nondeterministic generator'
    print(f'Reference catalog: {len(inspector.ids)} unique anchors, {len(inspector.links)} links, {len(inspector.assets)} local images; complete geometry and deterministic HTML passed')
if __name__=='__main__':main()
